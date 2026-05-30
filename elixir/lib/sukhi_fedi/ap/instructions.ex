# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.AP.Instructions do
  @moduledoc """
  Parses and executes instructions returned by the Bun
  `fedify.inbox.v1` NATS Micro endpoint.
  """

  import Ecto.Query

  alias SukhiFedi.{Notes, Notifications, Outbox, Repo}
  alias SukhiFedi.Schema.{Follow, ConversationParticipant, Account, Note, Reaction}
  alias SukhiFedi.Relays
  alias SukhiFedi.Addons.PinnedNotes

  # How many recent public posts to replay to a brand-new follower so
  # their timeline isn't blank until our next outbound post.
  @backfill_limit 20

  # Delivery runs on a separate BEAM node with its own Oban supervisor
  # polling the :delivery queue. We reach its worker via the fully-
  # qualified worker string so the gateway has no compile-time dependency
  # on the delivery app.
  @delivery_worker "SukhiDelivery.Delivery.Worker"
  @delivery_queue "delivery"

  @public_ns "https://www.w3.org/ns/activitystreams#Public"
  @as_public "Public"

  @doc """
  Executes an instruction map returned from the fedify.inbox.v1 endpoint.
  """
  @spec execute(map()) :: :ok
  def execute(%{"action" => "save", "object" => object_data}) do
    maybe_handle_dm(object_data)
    maybe_handle_relay_accept(object_data)
    maybe_handle_follow_accept(object_data)
    maybe_mirror_create_note(object_data)
    maybe_handle_reaction(object_data)
    maybe_notify_announce(object_data)
    maybe_handle_pin_unpin(object_data)
    maybe_handle_delete(object_data)
    maybe_handle_undo(object_data)
    :ok
  end

  def execute(%{
        "action" => "save_and_reply",
        "save" => save_data,
        "reply" => reply,
        "inbox" => inbox_url
      }) do
    insert_follow(save_data)
    maybe_notify_follow(save_data)

    followee_uri = save_data["followeeUri"]

    Oban.insert!(
      SukhiFedi.Oban,
      Oban.Job.new(
        %{raw_json: reply, inbox_url: inbox_url, actor_uri: followee_uri},
        worker: @delivery_worker,
        queue: @delivery_queue
      )
    )

    # Nudge the follower to refresh our cached actor (so their follower
    # count reflects us immediately instead of after their 24h TTL).
    maybe_enqueue_actor_update(followee_uri, inbox_url)

    # Replay our recent public posts to the new follower's inbox. Without
    # this they only see posts published after the Accept lands, which
    # means a quiet account looks empty on their server until we post
    # something new.
    maybe_backfill_recent_notes(followee_uri, inbox_url)

    :ok
  end

  def execute(%{"action" => "ignore"}) do
    :ok
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  defp insert_follow(%{"follow" => follow_data} = data) do
    followee_uri = data["followeeUri"]

    account =
      if followee_uri do
        username =
          followee_uri
          |> URI.parse()
          |> Map.get(:path, "")
          |> String.split("/")
          |> List.last()

        SukhiFedi.Accounts.by_local_username(username)
      else
        SukhiFedi.Accounts.by_local_username(data["followee_username"])
      end

    if account && follow_data do
      follower_uri = extract_uri(follow_data["actor"])

      if is_binary(follower_uri) do
        %Follow{
          follower_uri: follower_uri,
          followee_id: account.id,
          state: "accepted"
        }
        |> Repo.insert(on_conflict: :nothing)
      end
    end
  end

  defp insert_follow(_), do: :ok

  # fedify's `follow.toJsonLd({ contextLoader })` inlines the resolved
  # actor object (full Person JSON-LD) into the `actor` field instead of
  # leaving it as a bare ID string. Accept both shapes.
  defp extract_uri(uri) when is_binary(uri), do: uri
  defp extract_uri(%{"id" => id}) when is_binary(id), do: id
  defp extract_uri(%{"@id" => id}) when is_binary(id), do: id
  defp extract_uri(_), do: nil

  # Misskey and its forks signal a quote-note with one of several
  # top-level fields on the Object; FEP-e232 servers instead put it in a
  # `tag` Link. Accept all of them.
  defp extract_quote_uri(note) when is_map(note) do
    extract_uri(note["quoteUrl"]) ||
      extract_uri(note["quoteUri"]) ||
      extract_uri(note["_misskey_quote"]) ||
      quote_uri_from_tag(note["tag"])
  end

  defp extract_quote_uri(_), do: nil

  # FEP-e232: the quote travels as a `tag` entry of type `Link` whose
  # `rel` marks it a quote (Misskey's `_misskey_quote` rel or the
  # FEP-e232 rel). Return the first matching `href`.
  defp quote_uri_from_tag(tags) when is_list(tags) do
    Enum.find_value(tags, fn
      %{"type" => "Link"} = link ->
        if quote_rel?(link["rel"]), do: extract_uri(link["href"]), else: nil

      _ ->
        nil
    end)
  end

  defp quote_uri_from_tag(_), do: nil

  defp quote_rel?(rel) when is_binary(rel), do: quote_rel_match?(rel)
  defp quote_rel?(rels) when is_list(rels), do: Enum.any?(rels, &quote_rel_match?/1)
  defp quote_rel?(_), do: false

  defp quote_rel_match?(rel) when is_binary(rel) do
    String.contains?(rel, "_misskey_quote") or String.contains?(rel, "e232")
  end

  defp quote_rel_match?(_), do: false

  # MFM (Misskey Flavored Markdown) source travels out of band of the
  # rendered `content` — as `_misskey_content` or a `source` object.
  # Keep it so the source round-trips instead of collapsing to HTML.
  defp extract_mfm(note) when is_map(note) do
    case note["_misskey_content"] do
      s when is_binary(s) and s != "" -> s
      _ -> mfm_from_source(note["source"])
    end
  end

  defp extract_mfm(_), do: nil

  defp mfm_from_source(%{"content" => s}) when is_binary(s) and s != "", do: s
  defp mfm_from_source(_), do: nil

  defp maybe_enqueue_actor_update(followee_uri, inbox_url)
       when is_binary(followee_uri) and is_binary(inbox_url) do
    username =
      followee_uri
      |> URI.parse()
      |> Map.get(:path, "")
      |> String.split("/")
      |> List.last()

    case SukhiFedi.Accounts.by_local_username(username) do
      %Account{} = account ->
        update_json = SukhiFedi.AP.ActorJson.build_update(account)

        Oban.insert!(
          SukhiFedi.Oban,
          Oban.Job.new(
            %{raw_json: update_json, inbox_url: inbox_url, actor_uri: followee_uri},
            worker: @delivery_worker,
            queue: @delivery_queue
          )
        )

      _ ->
        :ok
    end
  end

  defp maybe_enqueue_actor_update(_, _), do: :ok

  defp maybe_backfill_recent_notes(followee_uri, follower_inbox)
       when is_binary(followee_uri) and is_binary(follower_inbox) do
    username =
      followee_uri
      |> URI.parse()
      |> Map.get(:path, "")
      |> String.split("/")
      |> List.last()

    case SukhiFedi.Accounts.by_local_username(username) do
      %Account{id: account_id} ->
        from(n in Note,
          where: n.account_id == ^account_id and n.visibility == "public",
          order_by: [desc: n.created_at],
          limit: ^@backfill_limit,
          select: %{
            id: n.id,
            content: n.content,
            quote_of_ap_id: n.quote_of_ap_id,
            in_reply_to_ap_id: n.in_reply_to_ap_id
          }
        )
        |> Repo.all()
        |> Enum.each(fn n ->
          Outbox.enqueue(
            "sns.outbox.follow.backfill",
            "note",
            to_string(n.id),
            %{
              account_id: account_id,
              note_id: n.id,
              content: n.content,
              quote_of_ap_id: n.quote_of_ap_id,
              in_reply_to_ap_id: n.in_reply_to_ap_id,
              follower_inbox: follower_inbox
            }
          )
        end)

      _ ->
        :ok
    end
  end

  defp maybe_backfill_recent_notes(_, _), do: :ok

  # Detect incoming DMs: Create activity wrapping a Note whose `to` doesn't
  # include the AS#Public URI. Record conversation participants for inbox queries.
  defp maybe_handle_dm(%{"type" => "Create", "object" => object, "actor" => actor_uri})
       when is_map(object) do
    to_list = normalize_collection(object["to"] || [])

    is_direct =
      Enum.all?(to_list, fn recipient ->
        recipient != @public_ns and recipient != @as_public
      end) and length(to_list) > 0

    if is_direct do
      conversation_ap_id =
        object["context"] || object["conversation"] || object["id"]

      domain = SukhiFedi.Config.domain!()
      local_recipients = Enum.filter(to_list, &String.contains?(&1, domain))

      # The note belongs to the sender, not the recipient. Resolve (and,
      # on first contact, ingest) the sender's account once: it authors
      # the stored note and joins the conversation so the recipient sees
      # who the DM is from.
      sender = resolve_dm_sender(object, actor_uri)

      record_sender_participant(conversation_ap_id, sender)
      Enum.each(local_recipients, &record_participant(conversation_ap_id, &1))

      # Persist only when a local account is actually addressed. Idempotent
      # on the note's AP id, so re-delivery doesn't duplicate.
      if local_recipients != [] do
        save_inbound_dm_note(object, sender, conversation_ap_id)
      end
    end
  end

  defp maybe_handle_dm(_), do: :ok

  defp record_participant(conversation_ap_id, actor_uri) when is_binary(conversation_ap_id) do
    domain = SukhiFedi.Config.domain!()
    username = actor_uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()

    account =
      if String.contains?(actor_uri, domain),
        do: SukhiFedi.Accounts.by_local_username(username),
        else: nil

    if account do
      # A received DM marks the local participant unread. Only local
      # accounts get a row (a remote sender has none); this path is the
      # remote→local receive, so the row being written is the recipient's.
      %ConversationParticipant{}
      |> ConversationParticipant.changeset(%{
        conversation_ap_id: conversation_ap_id,
        account_id: account.id,
        unread: true
      })
      |> Repo.insert(
        on_conflict: [set: [unread: true]],
        conflict_target: [:conversation_ap_id, :account_id]
      )
    end
  end

  defp record_participant(_, _), do: :ok

  # The sender authors the DM. `attributedTo` is the canonical author;
  # fall back to the Create's actor. Returns nil if we can't resolve or
  # ingest them — then the note and participant are skipped rather than
  # mis-attributed to the recipient.
  defp resolve_dm_sender(object, actor_uri) do
    uri = extract_uri(object["attributedTo"]) || actor_uri

    case uri && resolve_or_ingest_actor(uri) do
      {:ok, %Account{} = account} -> account
      _ -> nil
    end
  end

  # The sender joins the conversation so it shows in the recipient's
  # `accounts` ("who is this from"). Their unread flag is irrelevant —
  # they don't read here — so it stays false.
  defp record_sender_participant(conversation_ap_id, %Account{id: account_id})
       when is_binary(conversation_ap_id) do
    %ConversationParticipant{}
    |> ConversationParticipant.changeset(%{
      conversation_ap_id: conversation_ap_id,
      account_id: account_id,
      unread: false
    })
    |> Repo.insert(
      on_conflict: [set: [unread: false]],
      conflict_target: [:conversation_ap_id, :account_id]
    )
  end

  defp record_sender_participant(_, _), do: :ok

  # Mirror the inbound DM into `notes`, authored by the sender. Keyed on
  # the note's AP id so threading resolves and re-delivery is a no-op.
  defp save_inbound_dm_note(object, %Account{id: account_id}, conversation_ap_id) do
    attrs = %{
      "account_id" => account_id,
      "content" => object["content"] || "",
      "ap_id" => object["id"],
      "visibility" => "direct",
      "conversation_ap_id" => conversation_ap_id,
      "in_reply_to_ap_id" => extract_uri(object["inReplyTo"])
    }

    %Note{}
    |> Note.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: :ap_id)
  end

  defp save_inbound_dm_note(_, _, _), do: :ok

  # When we receive Accept(Follow) where the actor is a known relay, mark it accepted.
  defp maybe_handle_relay_accept(%{"type" => "Accept", "actor" => actor_uri})
       when is_binary(actor_uri) do
    Relays.accept(actor_uri)
    :ok
  end

  defp maybe_handle_relay_accept(_), do: :ok

  # Inbound Accept(Follow): the remote followee accepted our outbound
  # Follow. Flip the local Follow row from `pending` → `accepted` so
  # home-timeline visibility kicks in.
  #
  # We match on the inner Follow's `actor` (= our local actor URI) and
  # `object` (= remote followee URI, which maps to a shadow Account).
  # If the Accept embeds only the Follow's URI (a string), we skip —
  # we don't currently persist the outbound Follow's AP id.
  defp maybe_handle_follow_accept(%{
         "type" => "Accept",
         "object" => %{"type" => "Follow"} = inner
       }) do
    with follower_uri when is_binary(follower_uri) <- extract_uri(inner["actor"]),
         followee_uri when is_binary(followee_uri) <- extract_uri(inner["object"]),
         %Account{id: followee_id} <- Repo.get_by(Account, actor_uri: followee_uri) do
      from(f in Follow,
        where: f.follower_uri == ^follower_uri and f.followee_id == ^followee_id
      )
      |> Repo.update_all(set: [state: "accepted"])

      :ok
    else
      _ -> :ok
    end
  end

  defp maybe_handle_follow_accept(_), do: :ok

  # Inbound Create(Note) → mirror to the `notes` table so Timelines.home /
  # Timelines.public can see it. DMs (no AS#Public in `to`/`cc`) are
  # routed by `maybe_handle_dm`, which writes its own Note row scoped
  # to the local recipient; we skip them here to avoid double-insert.
  defp maybe_mirror_create_note(
         %{"type" => "Create", "object" => %{"type" => type} = note} = activity
       )
       when type in ["Note", "Article", "Question"] do
    if dm_addressing?(note) do
      :ok
    else
      ap_id = note["id"]
      attributed_to = extract_uri(note["attributedTo"]) || extract_uri(activity["actor"])

      with true <- is_binary(ap_id),
           true <- is_binary(attributed_to),
           {:ok, %Account{id: account_id}} <- resolve_or_ingest_actor(attributed_to) do
        attrs = %{
          "account_id" => account_id,
          "content" => note["content"] || "",
          "ap_id" => ap_id,
          "visibility" => visibility_from(note),
          "in_reply_to_ap_id" => extract_uri(note["inReplyTo"]),
          "quote_of_ap_id" => extract_quote_uri(note),
          "mfm" => extract_mfm(note)
        }

        case %Note{}
             |> Note.changeset(attrs)
             |> Repo.insert(on_conflict: :nothing, conflict_target: :ap_id) do
          {:ok, %Note{id: nid}} when not is_nil(nid) ->
            SukhiFedi.Tags.upsert_for_note(nid, note["content"])
            notify_mentions(note, nid, account_id)
            fetch_referenced_notes(attrs)
            :ok

          _ ->
            :ok
        end
      else
        _ -> :ok
      end
    end
  end

  defp maybe_mirror_create_note(_), do: :ok

  # Best-effort: pull the reply parent and the quoted note so threading
  # (`in_reply_to_id`) and quote rendering resolve to local rows.
  # NoteFetcher checks the DB first, so this only hits the network on a
  # genuine miss; one level only (the fetched note stores its own
  # in_reply_to_ap_id but we don't recurse). Failures are ignored — the
  # reply/quote is already stored, it just won't link until we see the
  # referenced note another way.
  defp fetch_referenced_notes(attrs) do
    for key <- ["in_reply_to_ap_id", "quote_of_ap_id"],
        uri = attrs[key],
        is_binary(uri) do
      # Truly best-effort: the fetch goes over NATS to Bun, so a down /
      # unreachable peer must never fail the inbox write. Swallow both
      # errors and exits (e.g. NATS not connected).
      try do
        SukhiFedi.Federation.NoteFetcher.fetch_and_mirror(uri)
      rescue
        _ -> :error
      catch
        _kind, _reason -> :error
      end
    end

    :ok
  end

  # A mirrored note can name local users in its AP `tag` array. Notify
  # each — this is the `mention` notification type. DM-addressed notes
  # never reach here (routed by `maybe_handle_dm`).
  defp notify_mentions(note, note_id, author_id) do
    note
    |> Map.get("tag")
    |> List.wrap()
    |> Enum.each(fn
      %{"type" => "Mention", "href" => href} when is_binary(href) ->
        case local_account_id_from_uri(href) do
          nil ->
            :ok

          local_id ->
            Notifications.create(%{
              account_id: local_id,
              from_account_id: author_id,
              note_id: note_id,
              type: "mention"
            })
        end

      _ ->
        :ok
    end)

    :ok
  end

  # Inbound `Like` (Mastodon favourite) or `EmojiReact` (Misskey custom
  # emoji reaction) on a note we can resolve → materialise a `reactions`
  # row and notify the note's author. The reaction already happened on
  # the remote side, so the row is inserted directly: no outbox event,
  # because re-broadcasting someone else's reaction would be wrong.
  defp maybe_handle_reaction(
         %{"type" => type, "actor" => actor_uri, "object" => object} = activity
       )
       when type in ["Like", "EmojiReact"] and is_binary(actor_uri) do
    with %Note{id: note_id, account_id: author_id} <- resolve_target_note(object),
         {:ok, %Account{id: reactor_id}} <- resolve_or_ingest_actor(actor_uri) do
      stored_emoji = stored_reaction_emoji(activity, actor_uri)

      %Reaction{}
      |> Reaction.changeset(%{
        account_id: reactor_id,
        note_id: note_id,
        emoji: stored_emoji
      })
      |> Repo.insert(on_conflict: :nothing)

      # Mastodon clients have no `reaction` notification type, so a
      # custom-emoji reaction surfaces as `favourite` — the emoji itself
      # lives on the `reactions` row for richer (Misskey) clients.
      Notifications.create(%{
        account_id: author_id,
        from_account_id: reactor_id,
        note_id: note_id,
        type: "favourite"
      })
    end

    :ok
  end

  defp maybe_handle_reaction(_), do: :ok

  # Compute the storage key for `reactions.emoji`:
  # - missing/blank content → favourite star (plain Mastodon Like)
  # - unicode glyph → stored verbatim
  # - `:shortcode:` → namespaced with actor's host, and any matching
  #   `tag` Emoji entry is upserted into the custom emoji directory
  defp stored_reaction_emoji(activity, actor_uri) do
    content = activity["content"]

    cond do
      not is_binary(content) or content == "" ->
        Notes.favourite_emoji()

      not String.starts_with?(content, ":") ->
        content

      true ->
        domain = actor_host(actor_uri)
        upsert_emoji_from_activity(content, activity["tag"], domain)
        SukhiFedi.CustomEmojis.namespaced(content, domain)
    end
  end

  defp actor_host(actor_uri) do
    case URI.parse(actor_uri) do
      %URI{host: h} when is_binary(h) -> h
      _ -> nil
    end
  end

  # `tag` is sometimes a list, sometimes a single map (Misskey occasionally).
  defp upsert_emoji_from_activity(_content, _tag, nil), do: :ok

  defp upsert_emoji_from_activity(content, tag, domain) do
    shortcode =
      case Regex.run(~r/^:([^:]+):$/, content) do
        [_, s] -> s
        _ -> nil
      end

    entry = find_emoji_tag(tag, content)

    if shortcode && is_map(entry) do
      SukhiFedi.CustomEmojis.upsert_from_tag(shortcode, entry, domain)
    else
      :ok
    end
  end

  defp find_emoji_tag(tag, name) when is_list(tag) do
    Enum.find(tag, fn
      %{"type" => "Emoji", "name" => ^name} -> true
      _ -> false
    end)
  end

  defp find_emoji_tag(%{"type" => "Emoji", "name" => name} = t, name), do: t
  defp find_emoji_tag(_, _), do: nil

  # Inbound `Announce` of a local note → reblog notification.
  defp maybe_notify_announce(%{
         "type" => "Announce",
         "actor" => actor_uri,
         "object" => object_uri
       }) do
    with %Note{id: note_id, account_id: recipient_id} <- resolve_target_note(object_uri),
         {:ok, %Account{id: from_id}} <- resolve_or_ingest_actor(actor_uri) do
      Notifications.create(%{
        account_id: recipient_id,
        from_account_id: from_id,
        note_id: note_id,
        type: "reblog"
      })
    end

    :ok
  end

  defp maybe_notify_announce(_), do: :ok

  # Inbound `Follow` (already auto-accepted via save_and_reply) → follow
  # notification for the local followee.
  defp maybe_notify_follow(%{"follow" => follow_data} = data) do
    with %Account{id: followee_id} <- local_followee(data),
         follower_uri when is_binary(follower_uri) <- extract_uri(follow_data["actor"]),
         {:ok, %Account{id: from_id}} <- resolve_or_ingest_actor(follower_uri) do
      Notifications.create(%{
        account_id: followee_id,
        from_account_id: from_id,
        type: "follow"
      })
    end

    :ok
  end

  defp maybe_notify_follow(_), do: :ok

  defp local_followee(%{"followeeUri" => uri}) when is_binary(uri) do
    username = uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()
    SukhiFedi.Accounts.by_local_username(username)
  end

  defp local_followee(%{"followee_username" => u}) when is_binary(u) do
    SukhiFedi.Accounts.by_local_username(u)
  end

  defp local_followee(_), do: nil

  # AS#Public in to/cc ⇒ not a DM. We treat absence-of-public as the DM
  # signal (matches `maybe_handle_dm`'s heuristic).
  defp dm_addressing?(note) do
    to = normalize_collection(note["to"] || [])
    cc = normalize_collection(note["cc"] || [])
    audience = to ++ cc

    audience != [] and
      Enum.all?(audience, fn r -> r != @public_ns and r != @as_public end)
  end

  defp visibility_from(note) do
    to = normalize_collection(note["to"] || [])
    cc = normalize_collection(note["cc"] || [])

    public_in_to = Enum.any?(to, &public?/1)
    public_in_cc = Enum.any?(cc, &public?/1)
    has_followers_addr = Enum.any?(to ++ cc, &String.ends_with?(&1 || "", "/followers"))

    cond do
      public_in_to -> "public"
      public_in_cc -> "unlisted"
      has_followers_addr -> "followers"
      true -> "direct"
    end
  end

  defp public?(uri) when is_binary(uri), do: uri == @public_ns or uri == @as_public
  defp public?(_), do: false

  # Look up an existing shadow Account by actor_uri, otherwise fetch +
  # upsert via the federation client. Local actor URIs (host == ours)
  # are matched by username.
  defp resolve_or_ingest_actor(actor_uri) do
    domain = SukhiFedi.Config.domain!()

    cond do
      String.contains?(actor_uri, domain) ->
        username =
          actor_uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()

        case SukhiFedi.Accounts.by_local_username(username) do
          %Account{} = a -> {:ok, a}
          nil -> {:error, :no_local_actor}
        end

      true ->
        case Repo.get_by(Account, actor_uri: actor_uri) do
          %Account{} = a ->
            {:ok, a}

          nil ->
            with {:ok, json} <- SukhiFedi.Federation.ActorFetcher.fetch(actor_uri),
                 {:ok, %Account{} = a} <-
                   SukhiFedi.Federation.RemoteAccounts.upsert_from_actor_json(json) do
              {:ok, a}
            else
              _ -> {:error, :ingest_failed}
            end
        end
    end
  end

  # Handle Add/Remove targeting a featured collection (pinned/unpinned posts).
  defp maybe_handle_pin_unpin(%{
         "type" => "Add",
         "actor" => actor_uri,
         "object" => note_uri,
         "target" => target_uri
       })
       when is_binary(actor_uri) and is_binary(note_uri) and is_binary(target_uri) do
    domain = SukhiFedi.Config.domain!()
    username = actor_uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()

    account =
      if String.contains?(actor_uri, domain),
        do: SukhiFedi.Accounts.by_local_username(username),
        else: nil

    if account && String.ends_with?(target_uri, "/featured") do
      note = Repo.get_by(SukhiFedi.Schema.Note, ap_id: note_uri)
      if note, do: PinnedNotes.pin(account.id, note.id)
    end
  end

  defp maybe_handle_pin_unpin(%{
         "type" => "Remove",
         "actor" => actor_uri,
         "object" => note_uri,
         "target" => target_uri
       })
       when is_binary(actor_uri) and is_binary(note_uri) and is_binary(target_uri) do
    domain = SukhiFedi.Config.domain!()
    username = actor_uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()

    account =
      if String.contains?(actor_uri, domain),
        do: SukhiFedi.Accounts.by_local_username(username),
        else: nil

    if account && String.ends_with?(target_uri, "/featured") do
      note = Repo.get_by(SukhiFedi.Schema.Note, ap_id: note_uri)
      if note, do: PinnedNotes.unpin(account.id, note.id)
    end
  end

  defp maybe_handle_pin_unpin(_), do: :ok

  # Inbound `Delete` activity: drop the local mirror of whatever the
  # remote actor is tombstoning. Object id can be a string or a Tombstone
  # map with `id`.
  defp maybe_handle_delete(%{"type" => "Delete", "object" => object}) do
    case extract_object_id(object) do
      nil ->
        :ok

      ap_id ->
        from(n in Note, where: n.ap_id == ^ap_id) |> Repo.delete_all()
        :ok
    end
  end

  defp maybe_handle_delete(_), do: :ok

  # Inbound `Undo`: reverse what the original activity materialised.
  # `Undo(Follow)` drops the follow row; `Undo(Like)` / `Undo(EmojiReact)`
  # drop the matching `reactions` row. `Undo(Announce)` stays a no-op —
  # we notify on inbound Announce but don't materialise a Boost row.
  defp maybe_handle_undo(%{"type" => "Undo", "actor" => actor_uri, "object" => inner})
       when is_binary(actor_uri) and is_map(inner) do
    case inner["type"] do
      "Follow" ->
        followee_uri = extract_object_id(inner["object"])
        followee_id = followee_uri && local_account_id_from_uri(followee_uri)

        if followee_id do
          from(f in Follow,
            where: f.follower_uri == ^actor_uri and f.followee_id == ^followee_id
          )
          |> Repo.delete_all()

          # Nudge the ex-follower to refresh our actor cache so its
          # follower count drops immediately instead of on the next
          # 24-hour TTL sweep. Heuristic inbox = `<actor>/inbox`;
          # works for Mastodon + fedify-based servers.
          maybe_enqueue_actor_update(followee_uri, actor_uri <> "/inbox")
        end

        :ok

      type when type in ["Like", "EmojiReact"] ->
        with %Note{id: note_id} <- resolve_target_note(inner["object"]),
             {:ok, %Account{id: reactor_id}} <- resolve_or_ingest_actor(actor_uri) do
          emoji = stored_reaction_emoji(inner, actor_uri)

          from(r in Reaction,
            where: r.account_id == ^reactor_id and r.note_id == ^note_id and r.emoji == ^emoji
          )
          |> Repo.delete_all()
        end

        :ok

      _ ->
        :ok
    end
  end

  defp maybe_handle_undo(_), do: :ok

  defp extract_object_id(id) when is_binary(id), do: id
  defp extract_object_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_object_id(_), do: nil

  # Resolve the Note an inbound activity targets. Local notes are
  # addressed by their synthesized AP id (`…/users/<name>/notes/<id>`,
  # see `NoteController`) and carry no `ap_id` column, so the trailing
  # path segment is the row id. Remote (mirrored) notes are matched by
  # their stored `ap_id`.
  defp resolve_target_note(object) do
    case extract_object_id(object) do
      uri when is_binary(uri) ->
        if String.contains?(uri, SukhiFedi.Config.domain!()) do
          last = (URI.parse(uri).path || "") |> String.split("/") |> List.last()

          case Integer.parse(last || "") do
            {id, ""} -> Repo.get(Note, id)
            _ -> nil
          end
        else
          Repo.get_by(Note, ap_id: uri)
        end

      _ ->
        nil
    end
  end

  defp local_account_id_from_uri(uri) when is_binary(uri) do
    domain = SukhiFedi.Config.domain!()

    if String.contains?(uri, domain) do
      username = uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()

      case SukhiFedi.Accounts.by_local_username(username) do
        nil -> nil
        account -> account.id
      end
    end
  end

  defp normalize_collection(list) when is_list(list), do: list
  defp normalize_collection(str) when is_binary(str), do: [str]
  defp normalize_collection(_), do: []
end
