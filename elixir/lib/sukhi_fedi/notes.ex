# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Notes do
  @moduledoc """
  Notes context. Reachable from the api plugin node via
  `SukhiApi.GatewayRpc.call(SukhiFedi.Notes, :fun, [args])`.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias SukhiFedi.{Outbox, Repo}
  alias SukhiFedi.Schema.{
    Account,
    Bookmark,
    Boost,
    ConversationParticipant,
    Media,
    Note,
    PinnedNote,
    Reaction
  }

  @favourite_emoji "⭐"

  # ── create ───────────────────────────────────────────────────────────────

  @doc """
  Create a note and enqueue the `sns.outbox.note.created` event atomically.

  A single Ecto.Multi transaction does both the `notes` insert and the
  `outbox` row. Combined with `Outbox.Relay` this delivers
  "DB commit = event durable" semantics.
  """
  def create_note(attrs) do
    Multi.new()
    |> Multi.insert(:note, Note.changeset(%Note{}, attrs))
    |> Outbox.enqueue_multi(
      :outbox_event,
      "sns.outbox.note.created",
      "note",
      & &1.note.id,
      fn %{note: note} ->
        %{
          note_id: note.id,
          account_id: note.account_id,
          visibility: note.visibility,
          content: note.content
        }
      end
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{note: note}} -> {:ok, Repo.preload(note, [:account, :media])}
      {:error, :note, %Ecto.Changeset{} = cs, _} -> {:error, {:validation, SukhiFedi.Changeset.errors(cs)}}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Create a status from Mastodon-shaped input.

  Translates:
    * `spoiler_text` → `cw`
    * `media_ids[]`  → resolves Media rows owned by the same account,
      attaches via `note_media` and stamps `attached_at` in the same
      `Ecto.Multi`
    * `in_reply_to_id` → either a local Note id or an http(s) URI; in
      the URI case `Federation.NoteFetcher` mirrors the remote note
      first so we can store its `ap_id`
    * `quote_id` / `quoted_status_id` → `quote_of_ap_id` (same id/URI
      resolution as `in_reply_to_id`) — federates as a 引用ノート
    * `poll[options][]` (or JSON `poll: %{…}`) → inserts a Poll +
      PollOptions in the same transaction

  `visibility: "direct"` routes to a DM: `@user` / `@user@host`
  mentions are pulled from the text, resolved to recipient actors
  (WebFinger + shadow upsert on a remote miss), and the note federates
  via `sns.outbox.dm.created`. Returns `{:error, :dm_no_recipients}`
  when no mention resolves.
  """
  @spec create_status(Account.t() | integer(), map()) ::
          {:ok, Note.t()} | {:error, atom() | {:validation, map()}}
  def create_status(%Account{id: aid}, params), do: create_status(aid, params)

  def create_status(account_id, params) when is_integer(account_id) do
    visibility = normalize_visibility(params[:visibility] || params["visibility"] || "public")

    if visibility == "direct" do
      create_direct_status(account_id, params)
    else
      attrs =
        %{
          account_id: account_id,
          content: params[:status] || params["status"] || "",
          cw: params[:spoiler_text] || params["spoiler_text"] || params[:cw] || params["cw"],
          visibility: visibility
        }
        |> resolve_in_reply_to(params)
        |> resolve_quote(params)

      media_ids = list_media_ids(params)

      Multi.new()
      |> Multi.insert(:note, Note.changeset(%Note{}, attrs))
      |> attach_media(media_ids, account_id)
      |> Multi.run(:tags, fn _repo, %{note: n} ->
        {:ok, SukhiFedi.Tags.upsert_for_note(n.id, n.content)}
      end)
      |> attach_poll(params)
      |> Outbox.enqueue_multi(
        :outbox_event,
        "sns.outbox.note.created",
        "note",
        & &1.note.id,
        fn %{note: n} ->
          %{
            note_id: n.id,
            account_id: n.account_id,
            visibility: n.visibility,
            content: n.content,
            media_ids: media_ids,
            quote_of_ap_id: n.quote_of_ap_id,
            in_reply_to_ap_id: n.in_reply_to_ap_id
          }
        end
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{note: note}} ->
          {:ok, Repo.preload(note, [:account, :media]) |> with_refs()}

        {:error, :note, %Ecto.Changeset{} = cs, _} ->
          {:error, {:validation, SukhiFedi.Changeset.errors(cs)}}

        {:error, :media_check, :not_owned, _} ->
          {:error, :media_not_owned}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  # `visibility: "direct"` path of `create_status/2`. Mentions are
  # resolved to recipients, split into local vs remote: local recipients
  # are delivered in-process (a `conversation_participants` row — they
  # read the sender's single note through the conversation), remote ones
  # federate via `sns.outbox.dm.created`. The note carries a
  # `conversation_ap_id` (its own AP id for a new thread, the parent's
  # for a reply) so the federated `context` threads on the other side and
  # the DM shows up in everyone's `/api/v1/conversations`. Hashtags and
  # polls are skipped — a DM is private and point-to-point.
  defp create_direct_status(account_id, params) do
    content = params[:status] || params["status"] || ""

    with {:ok, sender} <- SukhiFedi.Accounts.get_account(account_id),
         recipients when recipients != [] <- resolve_mention_recipients(content) do
      remote_uris = for r <- recipients, not r.local?, do: r.actor_uri

      base_attrs =
        %{
          account_id: account_id,
          content: content,
          cw: params[:spoiler_text] || params["spoiler_text"] || params[:cw] || params["cw"],
          visibility: "direct"
        }
        |> resolve_in_reply_to(params)

      inherited_cid = reply_parent_conversation(params)
      media_ids = list_media_ids(params)

      Multi.new()
      |> Multi.insert(:note, Note.changeset(%Note{}, base_attrs))
      |> attach_media(media_ids, account_id)
      |> Multi.run(:dm, fn repo, %{note: note} ->
        cid = inherited_cid || dm_conversation_ap_id(sender.username, note.id)

        {:ok, note} =
          note
          |> Ecto.Changeset.change(conversation_ap_id: cid)
          |> repo.update()

        # Record every participant so the conversation's `accounts` is
        # complete (remote recipients have shadow accounts too). The
        # sender's own row stays read; a local recipient is unread;
        # remote rows just exist for the `accounts` list (their unread
        # flag is never read here).
        upsert_participant(repo, cid, account_id, false)
        Enum.each(recipients, fn r -> upsert_participant(repo, cid, r.account_id, r.local?) end)

        {:ok, note}
      end)
      |> maybe_enqueue_dm(remote_uris)
      |> Repo.transaction()
      |> case do
        {:ok, %{dm: note}} ->
          {:ok, Repo.preload(note, [:account, :media]) |> with_refs()}

        {:error, :note, %Ecto.Changeset{} = cs, _} ->
          {:error, {:validation, SukhiFedi.Changeset.errors(cs)}}

        {:error, :media_check, :not_owned, _} ->
          {:error, :media_not_owned}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    else
      {:error, :not_found} -> {:error, :account_not_found}
      [] -> {:error, :dm_no_recipients}
    end
  end

  # Only federate when there's a remote recipient. A purely local DM has
  # no inbox to POST to — its delivery is the participant rows above.
  defp maybe_enqueue_dm(multi, []), do: multi

  defp maybe_enqueue_dm(multi, remote_uris) do
    Outbox.enqueue_multi(
      multi,
      :outbox_event,
      "sns.outbox.dm.created",
      "note",
      & &1.dm.id,
      fn %{dm: n} ->
        %{
          note_id: n.id,
          account_id: n.account_id,
          content: n.content,
          recipient_actor_uris: remote_uris,
          in_reply_to_ap_id: n.in_reply_to_ap_id,
          conversation_ap_id: n.conversation_ap_id
        }
      end
    )
  end

  defp upsert_participant(repo, conversation_ap_id, account_id, unread) do
    %ConversationParticipant{}
    |> ConversationParticipant.changeset(%{
      conversation_ap_id: conversation_ap_id,
      account_id: account_id,
      unread: unread
    })
    |> repo.insert(
      on_conflict: [set: [unread: unread]],
      conflict_target: [:conversation_ap_id, :account_id]
    )
  end

  # A new DM thread is identified by the root note's own synthesized AP
  # id (local notes don't persist `ap_id`; it's derived on demand, same
  # convention the delivery node and AP controllers use).
  defp dm_conversation_ap_id(username, note_id),
    do: "https://#{SukhiFedi.Config.domain!()}/users/#{username}/notes/#{note_id}"

  # A DM reply inherits the parent's conversation so the whole thread
  # shares one `conversation_ap_id`. Resolved straight from the reply
  # target (a local note id or a remote note's AP URI) rather than via
  # `in_reply_to_ap_id`, which is null for local parents (local notes
  # don't persist an `ap_id`). Falls back to a new thread on a miss.
  defp reply_parent_conversation(params) do
    case params[:in_reply_to_id] || params["in_reply_to_id"] do
      nil -> nil
      id -> parent_note_conversation(id)
    end
  end

  defp parent_note_conversation(id) when is_integer(id),
    do: parent_note_conversation(to_string(id))

  defp parent_note_conversation(id) when is_binary(id) do
    query =
      if String.starts_with?(id, "http") do
        from(n in Note, where: n.ap_id == ^id, select: n.conversation_ap_id)
      else
        case parse_int(id) do
          nil -> nil
          int -> from(n in Note, where: n.id == ^int, select: n.conversation_ap_id)
        end
      end

    query && Repo.one(query)
  end

  defp parent_note_conversation(_), do: nil

  # Pull `@user` / `@user@host` handles from the note text and resolve
  # each to a recipient. The negative lookbehind keeps email addresses
  # from matching. Unresolvable handles are dropped. Each entry carries
  # whether the account is local, so the caller can split in-process
  # delivery from federation.
  @mention_re ~r/(?<![\w])@([\w]+)(?:@([\w.\-]+))?/

  defp resolve_mention_recipients(content) when is_binary(content) do
    domain = SukhiFedi.Config.domain!()

    @mention_re
    |> Regex.scan(content)
    |> Enum.map(fn
      [_, user, host] when host != "" -> "#{user}@#{host}"
      [_, user | _] -> user
    end)
    |> Enum.uniq()
    |> Enum.flat_map(fn handle ->
      case SukhiFedi.Accounts.lookup_by_acct(handle, resolve: true) do
        {:ok, %Account{} = account} ->
          [
            %{
              actor_uri: recipient_actor_uri(account, domain),
              account_id: account.id,
              local?: is_nil(account.domain)
            }
          ]

        _ ->
          []
      end
    end)
    |> Enum.uniq_by(& &1.actor_uri)
  end

  defp resolve_mention_recipients(_), do: []

  defp recipient_actor_uri(%Account{actor_uri: uri}, _domain) when is_binary(uri), do: uri
  defp recipient_actor_uri(%Account{username: u}, domain), do: "https://#{domain}/users/#{u}"

  # Optional poll block. Mastodon shape:
  #   poll[options][]=A&poll[options][]=B&poll[expires_in]=3600&poll[multiple]=false
  # JSON clients send `"poll": {"options": [...], ...}`. We accept
  # both; missing means "no poll", invalid means a Multi error so
  # the whole transaction rolls back.
  defp attach_poll(multi, params) do
    case extract_poll(params) do
      nil ->
        multi

      %{options: [_, _ | _] = options, expires_in: ein, multiple: multiple} ->
        expires_at =
          if is_integer(ein) and ein > 0 do
            DateTime.utc_now()
            |> DateTime.add(ein, :second)
            |> DateTime.truncate(:second)
          end

        multi
        |> Multi.run(:poll, fn repo, %{note: %SukhiFedi.Schema.Note{id: nid}} ->
          poll_cs =
            SukhiFedi.Schema.Poll.changeset(%SukhiFedi.Schema.Poll{}, %{
              note_id: nid,
              multiple: !!multiple,
              expires_at: expires_at
            })

          repo.insert(poll_cs)
        end)
        |> Multi.run(:poll_options, fn repo, %{poll: %{id: pid}} ->
          rows =
            options
            |> Enum.with_index()
            |> Enum.map(fn {title, idx} ->
              %{title: title, position: idx, poll_id: pid}
            end)

          {n, _} = repo.insert_all("poll_options", rows)
          {:ok, n}
        end)

      _ ->
        Multi.error(multi, :poll_invalid, :poll_needs_two_options)
    end
  end

  defp extract_poll(params) do
    opts =
      params[:poll] || params["poll"] ||
        params["poll[options][]"] || params[:poll_options] ||
        nil

    case opts do
      nil ->
        nil

      list when is_list(list) ->
        %{
          options: clean_options(list),
          expires_in: parse_int(params["poll[expires_in]"]),
          multiple: parse_bool(params["poll[multiple]"])
        }

      %{} = map ->
        %{
          options: clean_options(map["options"] || map[:options] || []),
          expires_in: parse_int(map["expires_in"] || map[:expires_in]),
          multiple: parse_bool(map["multiple"] || map[:multiple])
        }

      _ ->
        nil
    end
  end

  defp clean_options(list) when is_list(list) do
    list
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp clean_options(_), do: []

  defp parse_bool(true), do: true
  defp parse_bool(false), do: false
  defp parse_bool("true"), do: true
  defp parse_bool("1"), do: true
  defp parse_bool(_), do: false

  defp resolve_in_reply_to(attrs, params) do
    case params[:in_reply_to_id] || params["in_reply_to_id"] do
      nil ->
        attrs

      id ->
        case resolve_in_reply_to_ap_id(id) do
          nil -> attrs
          ap_id -> Map.put(attrs, :in_reply_to_ap_id, ap_id)
        end
    end
  end

  # Three shapes accepted:
  #   1. A local Note id (integer or numeric string) — look up the row's ap_id.
  #   2. An http(s) URI for a remote note already mirrored locally
  #      (`notes.ap_id` match) — return as-is.
  #   3. An http(s) URI we've never seen — fetch + mirror via
  #      `Federation.NoteFetcher`, then return the mirrored ap_id.
  #
  # On any fetch error we return nil rather than failing the whole
  # status-create so the user's reply still posts (just without the
  # threading link).
  defp resolve_in_reply_to_ap_id(id) when is_binary(id) do
    cond do
      String.starts_with?(id, "http://") or String.starts_with?(id, "https://") ->
        case SukhiFedi.Federation.NoteFetcher.fetch_and_mirror(id) do
          {:ok, %Note{ap_id: ap_id}} when is_binary(ap_id) -> ap_id
          _ -> nil
        end

      true ->
        case parse_int(id) do
          nil -> nil
          int_id -> Repo.one(from(n in Note, where: n.id == ^int_id, select: n.ap_id))
        end
    end
  end

  defp resolve_in_reply_to_ap_id(id) when is_integer(id) do
    Repo.one(from(n in Note, where: n.id == ^id, select: n.ap_id))
  end

  defp resolve_in_reply_to_ap_id(_), do: nil

  # `quote_id` / `quoted_status_id` → `quote_of_ap_id`. A Mastodon
  # client quoting a note is the caller for the outbound 引用ノote
  # plumbing. On any resolution miss we drop the quote rather than
  # failing the post.
  defp resolve_quote(attrs, params) do
    case params[:quote_id] || params["quote_id"] ||
           params[:quoted_status_id] || params["quoted_status_id"] do
      nil ->
        attrs

      id ->
        case quote_ap_id(id) do
          nil -> attrs
          ap_id -> Map.put(attrs, :quote_of_ap_id, ap_id)
        end
    end
  end

  # A quote target is an http(s) URI (fetched + mirrored on a miss) or
  # a local Note id. Local notes carry no `ap_id`, so synthesize the AP
  # URL the way `NoteController` publishes it.
  defp quote_ap_id(id) when is_binary(id) do
    if String.starts_with?(id, "http://") or String.starts_with?(id, "https://") do
      case SukhiFedi.Federation.NoteFetcher.fetch_and_mirror(id) do
        {:ok, %Note{ap_id: ap_id}} when is_binary(ap_id) -> ap_id
        _ -> nil
      end
    else
      case parse_int(id) do
        nil -> nil
        int_id -> note_ap_id(int_id)
      end
    end
  end

  defp quote_ap_id(id) when is_integer(id), do: note_ap_id(id)
  defp quote_ap_id(_), do: nil

  defp note_ap_id(note_id) do
    query =
      from(n in Note,
        join: a in assoc(n, :account),
        where: n.id == ^note_id,
        select: {n.ap_id, a.domain, a.username}
      )

    case Repo.one(query) do
      {ap_id, _domain, _username} when is_binary(ap_id) ->
        ap_id

      {nil, nil, username} ->
        "https://#{SukhiFedi.Config.domain!()}/users/#{username}/notes/#{note_id}"

      _ ->
        nil
    end
  end

  defp list_media_ids(params) do
    raw =
      params[:media_ids] || params["media_ids"] || params["media_ids[]"] || []

    raw
    |> List.wrap()
    |> Enum.map(&parse_int/1)
    |> Enum.reject(&is_nil/1)
  end

  defp attach_media(multi, [], _account_id), do: multi

  defp attach_media(multi, media_ids, account_id) do
    multi
    |> Multi.run(:media_check, fn repo, _changes ->
      owned =
        from(m in Media, where: m.id in ^media_ids and m.account_id == ^account_id, select: m.id)
        |> repo.all()

      if MapSet.equal?(MapSet.new(owned), MapSet.new(media_ids)) do
        {:ok, owned}
      else
        {:error, :not_owned}
      end
    end)
    |> Multi.run(:media_attached, fn repo, %{note: note, media_check: media_ids} ->
      # note_media is a pure join table — no timestamps in the schema.
      rows = Enum.map(media_ids, fn mid -> %{note_id: note.id, media_id: mid} end)
      {n, _} = repo.insert_all("note_media", rows)

      # Stamp attached_at so subsequent attach attempts (or the
      # idempotency check in MediaCtx.attach/3) treat these rows as
      # claimed. Only flips rows that haven't been claimed yet.
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      repo.update_all(
        from(m in Media, where: m.id in ^media_ids and is_nil(m.attached_at)),
        set: [attached_at: now]
      )

      {:ok, n}
    end)
  end

  # ── reads ────────────────────────────────────────────────────────────────

  @doc """
  Load a single note by id with the assocs Mastodon Status JSON
  needs: account, media, poll, reactions.
  """
  @spec get_note(integer() | binary()) :: {:ok, Note.t()} | {:error, :not_found}
  def get_note(id) do
    case parse_int(id) do
      nil ->
        {:error, :not_found}

      n ->
        case Repo.get(Note, n) do
          nil -> {:error, :not_found}
          note -> {:ok, Repo.preload(note, [:account, :media, :poll, :reactions]) |> with_refs()}
        end
    end
  end

  @doc """
  Enrich notes with the reply/quote reference fields the Mastodon view
  needs, resolving the stored AP ids to local rows in one batch query
  (no N+1):

    * `in_reply_to_id` / `in_reply_to_account_id` — the reply parent,
      when we hold it locally (else left nil; the reply still renders).
    * `quoted_note` — the quoted note with its account preloaded, for a
      nested-Status `quote` render.

  Accepts a list or a single note; anything else passes through.
  """
  @spec with_refs([Note.t()] | Note.t() | any()) :: [Note.t()] | Note.t() | any()
  def with_refs(notes) when is_list(notes) do
    refs =
      notes
      |> Enum.flat_map(fn n -> [n.in_reply_to_ap_id, n.quote_of_ap_id] end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    by_ap =
      if refs == [] do
        %{}
      else
        from(n in Note, where: n.ap_id in ^refs)
        |> Repo.all()
        |> Repo.preload(:account)
        |> Map.new(fn n -> {n.ap_id, n} end)
      end

    Enum.map(notes, fn n ->
      parent = n.in_reply_to_ap_id && Map.get(by_ap, n.in_reply_to_ap_id)
      quoted = n.quote_of_ap_id && Map.get(by_ap, n.quote_of_ap_id)

      %{
        n
        | in_reply_to_id: parent && parent.id,
          in_reply_to_account_id: parent && parent.account_id,
          quoted_note: quoted
      }
    end)
  end

  def with_refs(%Note{} = note), do: note |> List.wrap() |> with_refs() |> hd()
  def with_refs(other), do: other

  # ── delete ───────────────────────────────────────────────────────────────

  @doc """
  Delete a note. Owner-checked: returns `{:error, :forbidden}` if the
  caller doesn't own the note.

  Emits `sns.outbox.note.deleted` carrying the AP id so federated
  peers can scrub their cached copies.
  """
  @spec delete_note(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found | :forbidden}
  def delete_note(%Account{id: aid}, note_id), do: delete_note(aid, note_id)

  def delete_note(account_id, note_id) when is_integer(account_id) do
    case parse_int(note_id) do
      nil ->
        {:error, :not_found}

      n ->
        case Repo.get(Note, n) do
          nil ->
            {:error, :not_found}

          %Note{account_id: ^account_id} = note ->
            do_delete(note)

          %Note{} ->
            {:error, :forbidden}
        end
    end
  end

  defp do_delete(%Note{} = note) do
    Multi.new()
    |> Multi.delete(:note, note)
    |> Outbox.enqueue_multi(
      :outbox_event,
      "sns.outbox.note.deleted",
      "note",
      fn _ -> note.id end,
      fn _ ->
        %{note_id: note.id, ap_id: note.ap_id, account_id: note.account_id}
      end
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{note: deleted}} -> {:ok, deleted}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  # ── context (ancestors / descendants) ────────────────────────────────────

  @max_depth 60

  # How many missing ancestors to backfill from the origin per context
  # view. The walk is bounded by @max_depth; this separately caps the
  # number of synchronous remote fetches so opening one note can't fan
  # out into dozens of round-trips.
  @ancestor_backfill 20

  @doc """
  Build a Mastodon Context for a note: ancestors (parents up the
  reply chain) and descendants (replies down the tree). Capped at
  depth #{@max_depth} like Mastodon.

  Ancestors are backfilled on demand: walking up `in_reply_to_ap_id`,
  a parent we don't hold locally is fetched + mirrored via
  `Federation.NoteFetcher` (best-effort, up to #{@ancestor_backfill}
  fetches) so a reply opened in isolation still shows its thread.
  Descendants stay local-only — pulling a remote `replies` collection
  is a separate piece.
  """
  @spec context(integer() | binary()) ::
          {:ok, %{ancestors: [Note.t()], descendants: [Note.t()]}} | {:error, :not_found}
  def context(note_id) do
    case parse_int(note_id) do
      nil ->
        {:error, :not_found}

      n ->
        case Repo.get(Note, n) do
          nil ->
            {:error, :not_found}

          note ->
            note = Repo.preload(note, :account)

            {:ok,
             %{
               ancestors: with_refs(ancestors_of(note)),
               descendants: with_refs(descendants_of(note))
             }}
        end
    end
  end

  defp ancestors_of(%Note{in_reply_to_ap_id: nil}), do: []

  defp ancestors_of(%Note{in_reply_to_ap_id: parent_ap_id}) do
    walk_ancestors(parent_ap_id, [], 0, @ancestor_backfill)
  end

  defp walk_ancestors(_ap_id, acc, depth, _budget) when depth >= @max_depth,
    do: Enum.reverse(acc)

  defp walk_ancestors(nil, acc, _depth, _budget), do: Enum.reverse(acc)

  defp walk_ancestors(ap_id, acc, depth, budget) do
    case lookup_note_by_uri(ap_id) do
      %Note{} = note ->
        walk_ancestors(note.in_reply_to_ap_id, [note | acc], depth + 1, budget)

      nil ->
        # A local parent (its `ap_id` is NULL) resolves above by id, so a
        # miss is a remote ancestor we haven't mirrored — pull it from the
        # origin. Never federate-fetch one of our own URLs; a miss ends it.
        if budget > 0 and is_nil(local_note_id_from_uri(ap_id)) do
          case fetch_ancestor(ap_id) do
            %Note{} = note ->
              walk_ancestors(note.in_reply_to_ap_id, [note | acc], depth + 1, budget - 1)

            nil ->
              Enum.reverse(acc)
          end
        else
          Enum.reverse(acc)
        end
    end
  end

  # Best-effort backfill of one ancestor. The fetch goes over NATS to Bun;
  # a down peer / disconnected NATS must never crash the context read.
  defp fetch_ancestor(ap_id) do
    try do
      case SukhiFedi.Federation.NoteFetcher.fetch_and_mirror(ap_id) do
        {:ok, %Note{} = n} -> Repo.preload(n, [:account, :media])
        _ -> nil
      end
    rescue
      _ -> nil
    catch
      _kind, _reason -> nil
    end
  end

  defp descendants_of(note) do
    case local_note_ap_id(note) do
      nil -> []
      ap_id -> walk_descendants([ap_id], [], 0)
    end
  end

  defp walk_descendants(_frontier, acc, depth) when depth >= @max_depth, do: Enum.reverse(acc)
  defp walk_descendants([], acc, _depth), do: Enum.reverse(acc)

  defp walk_descendants(frontier, acc, depth) do
    children =
      from(n in Note,
        where: n.in_reply_to_ap_id in ^frontier,
        order_by: [asc: n.id],
        preload: [:account, :media]
      )
      |> Repo.all()

    case children do
      [] ->
        Enum.reverse(acc)

      _ ->
        next_frontier = Enum.map(children, &local_note_ap_id/1) |> Enum.reject(&is_nil/1)
        walk_descendants(next_frontier, Enum.reverse(children, acc), depth + 1)
    end
  end

  # Resolve a note by an AP URL that may be one of our own synthesized
  # local ids (`https://<domain>/users/<u>/notes/<id>`, whose row carries
  # a NULL `ap_id`) or a real remote `ap_id`.
  defp lookup_note_by_uri(uri) do
    query =
      case local_note_id_from_uri(uri) do
        nil -> from(n in Note, where: n.ap_id == ^uri)
        id -> from(n in Note, where: n.id == ^id)
      end

    Repo.one(from(n in query, preload: [:account, :media]))
  end

  # A note's public AP id: the stored `ap_id` for remote notes, or the
  # synthesized `/notes/<id>` URL for local ones (whose `ap_id` is NULL).
  # Needs `:account` preloaded; nil if neither applies.
  defp local_note_ap_id(%Note{ap_id: ap_id}) when is_binary(ap_id), do: ap_id

  defp local_note_ap_id(%Note{ap_id: nil, id: id, account: %Account{username: u, domain: nil}}),
    do: "https://#{SukhiFedi.Config.domain!()}/users/#{u}/notes/#{id}"

  defp local_note_ap_id(_), do: nil

  # The numeric id from one of our own synthesized note URLs; nil otherwise.
  defp local_note_id_from_uri(uri) when is_binary(uri) do
    domain = SukhiFedi.Config.domain!()

    case Regex.run(~r{^https?://#{Regex.escape(domain)}/users/[^/]+/notes/(\d+)$}, uri) do
      [_, id] -> String.to_integer(id)
      _ -> nil
    end
  end

  defp local_note_id_from_uri(_), do: nil

  # ── interactions: favourite / reblog / bookmark / pin ────────────────────

  @doc """
  The emoji a Mastodon-style favourite is stored as. A `Reaction` row
  carrying this emoji is a favourite; any other emoji is a Misskey-style
  custom reaction.
  """
  @spec favourite_emoji() :: String.t()
  def favourite_emoji, do: @favourite_emoji

  @doc """
  Mark a note as favourited by `account`. Idempotent — second call is
  a no-op. Emits `sns.outbox.like.created` on first insert (delivery
  node will translate to `Like` AP activity).
  """
  @spec favourite(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found}
  def favourite(%Account{id: aid}, note_id), do: favourite(aid, note_id)

  def favourite(account_id, note_id) when is_integer(account_id) do
    with_loaded_note(note_id, fn note ->
      case Repo.get_by(Reaction,
             account_id: account_id,
             note_id: note.id,
             emoji: @favourite_emoji
           ) do
        %Reaction{} ->
          {:ok, note}

        nil ->
          Multi.new()
          |> Multi.insert(
            :reaction,
            Reaction.changeset(%Reaction{}, %{
              account_id: account_id,
              note_id: note.id,
              emoji: @favourite_emoji
            })
          )
          |> Outbox.enqueue_multi(
            :outbox_event,
            "sns.outbox.like.created",
            "reaction",
            & &1.reaction.id,
            fn %{reaction: r} ->
              %{
                reaction_id: r.id,
                account_id: r.account_id,
                note_id: r.note_id,
                note_ap_id: note.ap_id,
                emoji: r.emoji
              }
            end
          )
          |> Repo.transaction()
          |> case do
            {:ok, _} ->
              SukhiFedi.Notifications.create(%{
                account_id: note.account_id,
                from_account_id: account_id,
                note_id: note.id,
                type: "favourite"
              })

              {:ok, note}

            {:error, _step, reason, _} ->
              {:error, reason}
          end
      end
    end)
  end

  @doc "Remove favourite. Idempotent. Emits `sns.outbox.like.undone` on actual delete."
  @spec unfavourite(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found}
  def unfavourite(%Account{id: aid}, note_id), do: unfavourite(aid, note_id)

  def unfavourite(account_id, note_id) when is_integer(account_id) do
    with_loaded_note(note_id, fn note ->
      case Repo.get_by(Reaction,
             account_id: account_id,
             note_id: note.id,
             emoji: @favourite_emoji
           ) do
        nil ->
          {:ok, note}

        %Reaction{} = r ->
          Multi.new()
          |> Multi.delete(:reaction, r)
          |> Outbox.enqueue_multi(
            :outbox_event,
            "sns.outbox.like.undone",
            "reaction",
            fn _ -> r.id end,
            fn _ ->
              %{
                reaction_id: r.id,
                account_id: r.account_id,
                note_id: r.note_id,
                note_ap_id: note.ap_id
              }
            end
          )
          |> Repo.transaction()
          |> case do
            {:ok, _} -> {:ok, note}
            {:error, _step, reason, _} -> {:error, reason}
          end
      end
    end)
  end

  @doc """
  React to a note with an arbitrary emoji (Misskey-style custom
  reaction). Idempotent per `(account, note, emoji)`. Emits
  `sns.outbox.reaction.created` so the delivery node federates an
  `EmojiReact`.

  Unlike `favourite/2` — the ⭐ special case that federates as a
  `Like` — this carries the emoji on the wire. No HTTP route reaches
  it yet; the Misskey client API that would is parked (OPEN_QUESTIONS
  Q3).
  """
  @spec react(Account.t() | integer(), integer() | binary(), String.t()) ::
          {:ok, Note.t()} | {:error, :not_found | term()}
  def react(%Account{id: aid}, note_id, emoji), do: react(aid, note_id, emoji)

  def react(account_id, note_id, emoji)
      when is_integer(account_id) and is_binary(emoji) do
    with_loaded_note(note_id, fn note ->
      case Repo.get_by(Reaction, account_id: account_id, note_id: note.id, emoji: emoji) do
        %Reaction{} ->
          {:ok, note}

        nil ->
          Multi.new()
          |> Multi.insert(
            :reaction,
            Reaction.changeset(%Reaction{}, %{
              account_id: account_id,
              note_id: note.id,
              emoji: emoji
            })
          )
          |> Outbox.enqueue_multi(
            :outbox_event,
            "sns.outbox.reaction.created",
            "reaction",
            & &1.reaction.id,
            fn %{reaction: r} ->
              %{
                reaction_id: r.id,
                account_id: r.account_id,
                note_id: r.note_id,
                note_ap_id: note.ap_id,
                emoji: r.emoji
              }
            end
          )
          |> Repo.transaction()
          |> case do
            {:ok, _} ->
              SukhiFedi.Notifications.create(%{
                account_id: note.account_id,
                from_account_id: account_id,
                note_id: note.id,
                type: "favourite"
              })

              {:ok, note}

            {:error, _step, reason, _} ->
              {:error, reason}
          end
      end
    end)
  end

  @doc "Remove a custom emoji reaction. Idempotent. Emits `sns.outbox.reaction.undone` on actual delete."
  @spec unreact(Account.t() | integer(), integer() | binary(), String.t()) ::
          {:ok, Note.t()} | {:error, :not_found | term()}
  def unreact(%Account{id: aid}, note_id, emoji), do: unreact(aid, note_id, emoji)

  def unreact(account_id, note_id, emoji)
      when is_integer(account_id) and is_binary(emoji) do
    with_loaded_note(note_id, fn note ->
      case Repo.get_by(Reaction, account_id: account_id, note_id: note.id, emoji: emoji) do
        nil ->
          {:ok, note}

        %Reaction{} = r ->
          Multi.new()
          |> Multi.delete(:reaction, r)
          |> Outbox.enqueue_multi(
            :outbox_event,
            "sns.outbox.reaction.undone",
            "reaction",
            fn _ -> r.id end,
            fn _ ->
              %{
                reaction_id: r.id,
                account_id: r.account_id,
                note_id: r.note_id,
                note_ap_id: note.ap_id,
                emoji: r.emoji
              }
            end
          )
          |> Repo.transaction()
          |> case do
            {:ok, _} -> {:ok, note}
            {:error, _step, reason, _} -> {:error, reason}
          end
      end
    end)
  end

  @doc "Reblog (Mastodon) / Boost (internal). Idempotent. Emits `sns.outbox.announce.created`."
  @spec reblog(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found}
  def reblog(%Account{id: aid}, note_id), do: reblog(aid, note_id)

  def reblog(account_id, note_id) when is_integer(account_id) do
    with_loaded_note(note_id, fn note ->
      case Repo.get_by(Boost, account_id: account_id, note_id: note.id) do
        %Boost{} ->
          {:ok, note}

        nil ->
          Multi.new()
          |> Multi.insert(
            :boost,
            Boost.changeset(%Boost{}, %{account_id: account_id, note_id: note.id})
          )
          |> Outbox.enqueue_multi(
            :outbox_event,
            "sns.outbox.announce.created",
            "boost",
            & &1.boost.id,
            fn %{boost: b} ->
              %{
                boost_id: b.id,
                account_id: b.account_id,
                note_id: b.note_id,
                note_ap_id: note.ap_id
              }
            end
          )
          |> Repo.transaction()
          |> case do
            {:ok, _} ->
              SukhiFedi.Notifications.create(%{
                account_id: note.account_id,
                from_account_id: account_id,
                note_id: note.id,
                type: "reblog"
              })

              {:ok, note}

            {:error, _step, reason, _} ->
              {:error, reason}
          end
      end
    end)
  end

  @doc "Undo reblog. Idempotent. Emits `sns.outbox.announce.undone` on actual delete."
  @spec unreblog(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found}
  def unreblog(%Account{id: aid}, note_id), do: unreblog(aid, note_id)

  def unreblog(account_id, note_id) when is_integer(account_id) do
    with_loaded_note(note_id, fn note ->
      case Repo.get_by(Boost, account_id: account_id, note_id: note.id) do
        nil ->
          {:ok, note}

        %Boost{} = b ->
          Multi.new()
          |> Multi.delete(:boost, b)
          |> Outbox.enqueue_multi(
            :outbox_event,
            "sns.outbox.announce.undone",
            "boost",
            fn _ -> b.id end,
            fn _ ->
              %{
                boost_id: b.id,
                account_id: b.account_id,
                note_id: b.note_id,
                note_ap_id: note.ap_id
              }
            end
          )
          |> Repo.transaction()
          |> case do
            {:ok, _} -> {:ok, note}
            {:error, _step, reason, _} -> {:error, reason}
          end
      end
    end)
  end

  @doc "Bookmark a note. Local-only — no outbox event. Idempotent."
  @spec bookmark(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found}
  def bookmark(%Account{id: aid}, note_id), do: bookmark(aid, note_id)

  def bookmark(account_id, note_id) when is_integer(account_id) do
    with_loaded_note(note_id, fn note ->
      _ =
        %Bookmark{account_id: account_id, note_id: note.id}
        |> Repo.insert(on_conflict: :nothing)

      {:ok, note}
    end)
  end

  @spec unbookmark(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found}
  def unbookmark(%Account{id: aid}, note_id), do: unbookmark(aid, note_id)

  def unbookmark(account_id, note_id) when is_integer(account_id) do
    with_loaded_note(note_id, fn note ->
      _ =
        Repo.delete_all(
          from(b in Bookmark, where: b.account_id == ^account_id and b.note_id == ^note.id)
        )

      {:ok, note}
    end)
  end

  @doc """
  Pin a note to the actor's featured collection. Owner-checked (you
  can only pin your own notes). Emits `sns.outbox.add.created` so
  remote followers can update their featured collection cache.
  """
  @spec pin(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found | :forbidden}
  def pin(%Account{id: aid}, note_id), do: pin(aid, note_id)

  def pin(account_id, note_id) when is_integer(account_id) do
    case load_owned_note(account_id, note_id) do
      {:error, e} ->
        {:error, e}

      {:ok, note} ->
        case Repo.get_by(PinnedNote, account_id: account_id, note_id: note.id) do
          %PinnedNote{} ->
            {:ok, note}

          nil ->
            Multi.new()
            |> Multi.insert(
              :pinned,
              PinnedNote.changeset(%PinnedNote{}, %{account_id: account_id, note_id: note.id})
            )
            |> Outbox.enqueue_multi(
              :outbox_event,
              "sns.outbox.add.created",
              "pinned_note",
              & &1.pinned.id,
              fn %{pinned: p} ->
                %{
                  pinned_id: p.id,
                  account_id: p.account_id,
                  note_id: p.note_id,
                  note_ap_id: note.ap_id
                }
              end
            )
            |> Repo.transaction()
            |> case do
              {:ok, _} -> {:ok, note}
              {:error, _step, reason, _} -> {:error, reason}
            end
        end
    end
  end

  @spec unpin(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found | :forbidden}
  def unpin(%Account{id: aid}, note_id), do: unpin(aid, note_id)

  def unpin(account_id, note_id) when is_integer(account_id) do
    case load_owned_note(account_id, note_id) do
      {:error, e} ->
        {:error, e}

      {:ok, note} ->
        case Repo.get_by(PinnedNote, account_id: account_id, note_id: note.id) do
          nil ->
            {:ok, note}

          %PinnedNote{} = p ->
            Multi.new()
            |> Multi.delete(:pinned, p)
            |> Outbox.enqueue_multi(
              :outbox_event,
              "sns.outbox.remove.created",
              "pinned_note",
              fn _ -> p.id end,
              fn _ ->
                %{
                  pinned_id: p.id,
                  account_id: p.account_id,
                  note_id: p.note_id,
                  note_ap_id: note.ap_id
                }
              end
            )
            |> Repo.transaction()
            |> case do
              {:ok, _} -> {:ok, note}
              {:error, _step, reason, _} -> {:error, reason}
            end
        end
    end
  end

  # ── counts + viewer flags ────────────────────────────────────────────────

  @doc """
  Per-note interaction counts. Used by `MastodonStatus.render/2`.

  Returns `%{replies: int, reblogs: int, favourites: int}` for a
  single note in three cheap counts.
  """
  @spec counts_for_note(integer()) :: %{
          replies: integer(),
          reblogs: integer(),
          favourites: integer()
        }
  def counts_for_note(note_id) when is_integer(note_id) do
    note = Repo.get(Note, note_id)
    ap_id = note && note.ap_id

    replies =
      case ap_id do
        nil -> 0
        ap -> Repo.aggregate(from(n in Note, where: n.in_reply_to_ap_id == ^ap), :count, :id)
      end

    reblogs = Repo.aggregate(from(b in Boost, where: b.note_id == ^note_id), :count, :id)

    favourites =
      Repo.aggregate(
        from(r in Reaction, where: r.note_id == ^note_id and r.emoji == ^@favourite_emoji),
        :count,
        :id
      )

    %{replies: replies, reblogs: reblogs, favourites: favourites}
  end

  @doc """
  Bulk variant: counts for many notes in one DB roundtrip per
  dimension. Returns a map keyed by note_id.
  """
  @spec counts_for_notes([integer()]) ::
          %{integer() => %{replies: integer(), reblogs: integer(), favourites: integer()}}
  def counts_for_notes([]), do: %{}

  def counts_for_notes(note_ids) when is_list(note_ids) do
    ap_ids =
      from(n in Note, where: n.id in ^note_ids, select: {n.id, n.ap_id})
      |> Repo.all()

    id_to_ap = Map.new(ap_ids)

    reblogs_map =
      from(b in Boost,
        where: b.note_id in ^note_ids,
        group_by: b.note_id,
        select: {b.note_id, count(b.id)}
      )
      |> Repo.all()
      |> Map.new()

    fav_map =
      from(r in Reaction,
        where: r.note_id in ^note_ids and r.emoji == ^@favourite_emoji,
        group_by: r.note_id,
        select: {r.note_id, count(r.id)}
      )
      |> Repo.all()
      |> Map.new()

    ap_id_list = id_to_ap |> Map.values() |> Enum.reject(&is_nil/1)

    replies_by_ap =
      if ap_id_list == [] do
        %{}
      else
        from(n in Note,
          where: n.in_reply_to_ap_id in ^ap_id_list,
          group_by: n.in_reply_to_ap_id,
          select: {n.in_reply_to_ap_id, count(n.id)}
        )
        |> Repo.all()
        |> Map.new()
      end

    Map.new(note_ids, fn id ->
      ap = Map.get(id_to_ap, id)

      {id,
       %{
         replies: Map.get(replies_by_ap, ap, 0),
         reblogs: Map.get(reblogs_map, id, 0),
         favourites: Map.get(fav_map, id, 0)
       }}
    end)
  end

  @doc """
  Misskey-style reaction breakdown for many notes in one DB roundtrip.
  Returns `%{note_id => [%{name, count, me}]}`, ordered by count desc
  then emoji asc for deterministic UI.

  Excludes the favourite emoji — those still flow through
  `favourites_count`/`favourited` to stay Mastodon-compatible.
  """
  @spec reactions_for_notes([integer()], integer() | nil) :: %{
          integer() => [%{name: String.t(), count: non_neg_integer(), me: boolean()}]
        }
  def reactions_for_notes(note_ids, viewer_id \\ nil)
  def reactions_for_notes([], _viewer_id), do: %{}

  def reactions_for_notes(note_ids, viewer_id) when is_list(note_ids) do
    rows =
      from(r in Reaction,
        where: r.note_id in ^note_ids and r.emoji != ^@favourite_emoji,
        group_by: [r.note_id, r.emoji],
        select: {r.note_id, r.emoji, count(r.id)}
      )
      |> Repo.all()

    mine =
      case viewer_id do
        nil ->
          MapSet.new()

        id when is_integer(id) ->
          from(r in Reaction,
            where:
              r.note_id in ^note_ids and r.account_id == ^id and r.emoji != ^@favourite_emoji,
            select: {r.note_id, r.emoji}
          )
          |> Repo.all()
          |> MapSet.new()
      end

    emoji_keys = rows |> Enum.map(fn {_, e, _} -> e end) |> Enum.uniq()
    urls = SukhiFedi.CustomEmojis.lookup_many(emoji_keys)

    rows
    |> Enum.group_by(fn {note_id, _emoji, _count} -> note_id end)
    |> Map.new(fn {note_id, group} ->
      list =
        group
        |> Enum.map(fn {_note_id, emoji, count} ->
          icon = Map.get(urls, emoji, %{})

          %{
            name: emoji,
            count: count,
            me: MapSet.member?(mine, {note_id, emoji}),
            url: Map.get(icon, :url),
            static_url: Map.get(icon, :static_url) || Map.get(icon, :url)
          }
        end)
        |> Enum.sort_by(fn %{count: c, name: n} -> {-c, n} end)

      {note_id, list}
    end)
  end

  @doc """
  Per-note viewer-context flags: `%{favourited, reblogged, bookmarked, pinned}`.
  """
  @spec viewer_flags(integer() | nil, integer()) :: %{
          favourited: boolean(),
          reblogged: boolean(),
          bookmarked: boolean(),
          pinned: boolean()
        }
  def viewer_flags(nil, _note_id),
    do: %{favourited: false, reblogged: false, bookmarked: false, pinned: false}

  def viewer_flags(account_id, note_id) when is_integer(account_id) and is_integer(note_id) do
    %{
      favourited:
        Repo.exists?(
          from(r in Reaction,
            where:
              r.account_id == ^account_id and r.note_id == ^note_id and
                r.emoji == ^@favourite_emoji
          )
        ),
      reblogged:
        Repo.exists?(
          from(b in Boost, where: b.account_id == ^account_id and b.note_id == ^note_id)
        ),
      bookmarked:
        Repo.exists?(
          from(b in Bookmark, where: b.account_id == ^account_id and b.note_id == ^note_id)
        ),
      pinned:
        Repo.exists?(
          from(p in PinnedNote, where: p.account_id == ^account_id and p.note_id == ^note_id)
        )
    }
  end

  @doc "Bulk variant of `viewer_flags/2`. Returns map keyed by note_id."
  @spec viewer_flags_many(integer() | nil, [integer()]) :: %{
          integer() => %{
            favourited: boolean(),
            reblogged: boolean(),
            bookmarked: boolean(),
            pinned: boolean()
          }
        }
  def viewer_flags_many(_account_id, []), do: %{}

  def viewer_flags_many(nil, note_ids) do
    Map.new(note_ids, fn id ->
      {id, %{favourited: false, reblogged: false, bookmarked: false, pinned: false}}
    end)
  end

  def viewer_flags_many(account_id, note_ids) when is_integer(account_id) and is_list(note_ids) do
    fav =
      from(r in Reaction,
        where:
          r.account_id == ^account_id and r.note_id in ^note_ids and
            r.emoji == ^@favourite_emoji,
        select: r.note_id
      )
      |> Repo.all()
      |> MapSet.new()

    reblog =
      from(b in Boost,
        where: b.account_id == ^account_id and b.note_id in ^note_ids,
        select: b.note_id
      )
      |> Repo.all()
      |> MapSet.new()

    bm =
      from(b in Bookmark,
        where: b.account_id == ^account_id and b.note_id in ^note_ids,
        select: b.note_id
      )
      |> Repo.all()
      |> MapSet.new()

    pin =
      from(p in PinnedNote,
        where: p.account_id == ^account_id and p.note_id in ^note_ids,
        select: p.note_id
      )
      |> Repo.all()
      |> MapSet.new()

    Map.new(note_ids, fn id ->
      {id,
       %{
         favourited: MapSet.member?(fav, id),
         reblogged: MapSet.member?(reblog, id),
         bookmarked: MapSet.member?(bm, id),
         pinned: MapSet.member?(pin, id)
       }}
    end)
  end

  @doc """
  List the viewer's bookmarked notes (newest bookmark first, Mastodon
  pagination opts).
  """
  @spec list_bookmarks(Account.t() | integer(), keyword() | map()) :: [Note.t()]
  def list_bookmarks(%Account{id: aid}, opts), do: list_bookmarks(aid, opts)

  def list_bookmarks(account_id, opts) when is_integer(account_id) do
    opts = normalize_kv(opts)
    limit = clamp_limit(Map.get(opts, :limit, 20))

    from(b in Bookmark,
      join: n in Note,
      on: b.note_id == n.id,
      where: b.account_id == ^account_id,
      order_by: [desc: b.id],
      limit: ^limit,
      select: n
    )
    |> Repo.all()
    |> Repo.preload([:account, :media, :tags])
    |> with_refs()
  end

  @doc "Same as list_bookmarks but for favourites (Reactions with the favourite emoji)."
  @spec list_favourites(Account.t() | integer(), keyword() | map()) :: [Note.t()]
  def list_favourites(%Account{id: aid}, opts), do: list_favourites(aid, opts)

  def list_favourites(account_id, opts) when is_integer(account_id) do
    opts = normalize_kv(opts)
    limit = clamp_limit(Map.get(opts, :limit, 20))

    from(r in Reaction,
      join: n in Note,
      on: r.note_id == n.id,
      where: r.account_id == ^account_id and r.emoji == ^@favourite_emoji,
      order_by: [desc: r.id],
      limit: ^limit,
      select: n
    )
    |> Repo.all()
    |> Repo.preload([:account, :media, :tags])
    |> with_refs()
  end

  defp with_loaded_note(note_id, fun) do
    case parse_int(note_id) do
      nil ->
        {:error, :not_found}

      n ->
        case Repo.get(Note, n) do
          nil -> {:error, :not_found}
          note -> fun.(note)
        end
    end
  end

  defp load_owned_note(account_id, note_id) do
    case parse_int(note_id) do
      nil ->
        {:error, :not_found}

      n ->
        case Repo.get(Note, n) do
          nil -> {:error, :not_found}
          %Note{account_id: ^account_id} = note -> {:ok, note}
          %Note{} -> {:error, :forbidden}
        end
    end
  end

  defp normalize_kv(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_kv(opts) when is_map(opts), do: opts

  defp clamp_limit(n) when is_integer(n) and n > 0 and n <= 40, do: n
  defp clamp_limit(_), do: 20

  # ── helpers ──────────────────────────────────────────────────────────────

  defp normalize_visibility(v) when v in ["public", "unlisted", "followers", "direct"], do: v
  # Mastodon's "private" maps to our "followers"
  defp normalize_visibility("private"), do: "followers"
  defp normalize_visibility(_), do: "public"

  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil
end
