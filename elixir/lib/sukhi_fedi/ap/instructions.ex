# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.AP.Instructions do
  @moduledoc """
  Parses and executes instructions returned by the Bun
  `fedify.inbox.v1` NATS Micro endpoint.
  """

  import Ecto.Query

  alias SukhiFedi.{Notifications, Outbox, Repo}
  alias SukhiFedi.Schema.{Follow, Object, ConversationParticipant, Account, Note}
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
    insert_object(object_data)
    maybe_handle_dm(object_data)
    maybe_handle_relay_accept(object_data)
    maybe_handle_follow_accept(object_data)
    maybe_mirror_create_note(object_data)
    maybe_notify_like(object_data)
    maybe_notify_announce(object_data)
    maybe_handle_pin_unpin(object_data)
    maybe_handle_delete(object_data)
    maybe_handle_undo(object_data)
    :ok
  end

  def execute(%{"action" => "save_and_reply", "save" => save_data, "reply" => reply, "inbox" => inbox_url}) do
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

  defp insert_object(data) do
    %Object{
      ap_id: data["id"],
      type: data["type"],
      actor_id: data["actor"],
      raw_json: data
    }
    |> Repo.insert(on_conflict: :nothing)
  end

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
          select: %{id: n.id, content: n.content}
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
  defp maybe_handle_dm(%{"type" => "Create", "object" => object, "actor" => actor_uri}) when is_map(object) do
    to_list = normalize_collection(object["to"] || [])

    is_direct =
      Enum.all?(to_list, fn recipient ->
        recipient != @public_ns and recipient != @as_public
      end) and length(to_list) > 0

    if is_direct do
      conversation_ap_id =
        object["context"] ||
          object["conversation"] ||
          object["id"]

      # Record the sender as a participant
      record_participant(conversation_ap_id, actor_uri)

      # Record each local recipient as a participant
      domain = SukhiFedi.Config.domain!()

      Enum.each(to_list, fn recipient_uri ->
        record_participant(conversation_ap_id, recipient_uri)

        # Save note locally if the recipient is a local account
        maybe_save_dm_note(recipient_uri, domain, object, actor_uri, conversation_ap_id)
      end)
    end
  end

  defp maybe_handle_dm(_), do: :ok

  defp record_participant(conversation_ap_id, actor_uri) when is_binary(conversation_ap_id) do
    domain = SukhiFedi.Config.domain!()
    username = actor_uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()
    account = if String.contains?(actor_uri, domain), do: SukhiFedi.Accounts.by_local_username(username), else: nil

    if account do
      %ConversationParticipant{}
      |> ConversationParticipant.changeset(%{
        conversation_ap_id: conversation_ap_id,
        account_id: account.id
      })
      |> Repo.insert(on_conflict: :nothing)
    end
  end

  defp record_participant(_, _), do: :ok

  defp maybe_save_dm_note(recipient_uri, domain, object, _actor_uri, conversation_ap_id) do
    if String.contains?(recipient_uri, domain) do
      username = recipient_uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()
      account = SukhiFedi.Accounts.by_local_username(username)

      if account do
        attrs = %{
          "account_id" => account.id,
          "content" => object["content"] || "",
          "visibility" => "direct",
          "conversation_ap_id" => conversation_ap_id,
          "in_reply_to_ap_id" => object["inReplyTo"]
        }

        %SukhiFedi.Schema.Note{}
        |> SukhiFedi.Schema.Note.changeset(attrs)
        |> Repo.insert(on_conflict: :nothing)
      end
    end
  end

  # When we receive Accept(Follow) where the actor is a known relay, mark it accepted.
  defp maybe_handle_relay_accept(%{"type" => "Accept", "actor" => actor_uri}) when is_binary(actor_uri) do
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
  defp maybe_mirror_create_note(%{"type" => "Create", "object" => %{"type" => type} = note} = activity)
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
          "in_reply_to_ap_id" => extract_uri(note["inReplyTo"])
        }

        case %Note{}
             |> Note.changeset(attrs)
             |> Repo.insert(on_conflict: :nothing, conflict_target: :ap_id) do
          {:ok, %Note{id: nid}} when not is_nil(nid) ->
            SukhiFedi.Tags.upsert_for_note(nid, note["content"])
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

  # Inbound `Like` on a local note → favourite notification for the
  # local author. We don't materialise the like itself yet, so look
  # up the target note by its AP id and notify if we own it.
  defp maybe_notify_like(%{"type" => "Like", "actor" => actor_uri, "object" => object_uri}) do
    with object_id when is_binary(object_id) <- extract_object_id(object_uri),
         %Note{id: note_id, account_id: recipient_id} <-
           Repo.get_by(Note, ap_id: object_id),
         {:ok, %Account{id: from_id}} <- resolve_or_ingest_actor(actor_uri) do
      Notifications.create(%{
        account_id: recipient_id,
        from_account_id: from_id,
        note_id: note_id,
        type: "favourite"
      })
    end

    :ok
  end

  defp maybe_notify_like(_), do: :ok

  # Inbound `Announce` of a local note → reblog notification.
  defp maybe_notify_announce(%{"type" => "Announce", "actor" => actor_uri, "object" => object_uri}) do
    with object_id when is_binary(object_id) <- extract_object_id(object_uri),
         %Note{id: note_id, account_id: recipient_id} <-
           Repo.get_by(Note, ap_id: object_id),
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
        username = actor_uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()

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
                 {:ok, %Account{} = a} <- SukhiFedi.Federation.RemoteAccounts.upsert_from_actor_json(json) do
              {:ok, a}
            else
              _ -> {:error, :ingest_failed}
            end
        end
    end
  end

  # Handle Add/Remove targeting a featured collection (pinned/unpinned posts).
  defp maybe_handle_pin_unpin(%{"type" => "Add", "actor" => actor_uri, "object" => note_uri, "target" => target_uri})
       when is_binary(actor_uri) and is_binary(note_uri) and is_binary(target_uri) do
    domain = SukhiFedi.Config.domain!()
    username = actor_uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()
    account = if String.contains?(actor_uri, domain), do: SukhiFedi.Accounts.by_local_username(username), else: nil

    if account && String.ends_with?(target_uri, "/featured") do
      note = Repo.get_by(SukhiFedi.Schema.Note, ap_id: note_uri)
      if note, do: PinnedNotes.pin(account.id, note.id)
    end
  end

  defp maybe_handle_pin_unpin(%{"type" => "Remove", "actor" => actor_uri, "object" => note_uri, "target" => target_uri})
       when is_binary(actor_uri) and is_binary(note_uri) and is_binary(target_uri) do
    domain = SukhiFedi.Config.domain!()
    username = actor_uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()
    account = if String.contains?(actor_uri, domain), do: SukhiFedi.Accounts.by_local_username(username), else: nil

    if account && String.ends_with?(target_uri, "/featured") do
      note = Repo.get_by(SukhiFedi.Schema.Note, ap_id: note_uri)
      if note, do: PinnedNotes.unpin(account.id, note.id)
    end
  end

  defp maybe_handle_pin_unpin(_), do: :ok

  # Inbound `Delete` activity: drop the local copy of whatever object the
  # remote actor is tombstoning. Object id can be a string or a Tombstone
  # map with `id`. Both `objects` and `notes` (if a local Note mirrored
  # the remote AP id) are scrubbed.
  defp maybe_handle_delete(%{"type" => "Delete", "object" => object}) do
    case extract_object_id(object) do
      nil -> :ok
      ap_id ->
        from(o in Object, where: o.ap_id == ^ap_id) |> Repo.delete_all()
        from(n in Note, where: n.ap_id == ^ap_id) |> Repo.delete_all()
        :ok
    end
  end

  defp maybe_handle_delete(_), do: :ok

  # Inbound `Undo(Follow)`: remove the matching follow row. Other Undo
  # variants (Like, Announce, …) are no-ops because we don't currently
  # materialise remote-actor-originated likes/boosts as local rows.
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

      _ ->
        :ok
    end
  end

  defp maybe_handle_undo(_), do: :ok

  defp extract_object_id(id) when is_binary(id), do: id
  defp extract_object_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_object_id(_), do: nil

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
