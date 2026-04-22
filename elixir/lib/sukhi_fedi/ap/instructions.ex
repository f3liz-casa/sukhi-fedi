# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.AP.Instructions do
  @moduledoc """
  Parses and executes instructions returned by the Bun
  `fedify.inbox.v1` NATS Micro endpoint.
  """

  import Ecto.Query

  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Follow, Object, ConversationParticipant, Account, Note}
  alias SukhiFedi.Relays
  alias SukhiFedi.Addons.PinnedNotes

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
    maybe_handle_pin_unpin(object_data)
    maybe_handle_delete(object_data)
    maybe_handle_undo(object_data)
    :ok
  end

  def execute(%{"action" => "save_and_reply", "save" => save_data, "reply" => reply, "inbox" => inbox_url}) do
    insert_follow(save_data)

    followee_uri = save_data["followeeUri"]

    Oban.insert!(
      Oban.Job.new(
        %{raw_json: reply, inbox_url: inbox_url, actor_uri: followee_uri},
        worker: @delivery_worker,
        queue: @delivery_queue
      )
    )

    # Nudge the follower to refresh our cached actor (so their follower
    # count reflects us immediately instead of after their 24h TTL).
    maybe_enqueue_actor_update(followee_uri, inbox_url)

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

        Repo.get_by(Account, username: username)
      else
        Repo.get_by(Account, username: data["followee_username"])
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

  # fedify's `follow.toJsonLd({ contextLoader })` inlines the resolved
  # actor object (full Person JSON-LD) into the `actor` field instead of
  # leaving it as a bare ID string. Accept both shapes.
  defp extract_uri(uri) when is_binary(uri), do: uri
  defp extract_uri(%{"id" => id}) when is_binary(id), do: id
  defp extract_uri(_), do: nil

  defp maybe_enqueue_actor_update(followee_uri, inbox_url)
       when is_binary(followee_uri) and is_binary(inbox_url) do
    username =
      followee_uri
      |> URI.parse()
      |> Map.get(:path, "")
      |> String.split("/")
      |> List.last()

    case Repo.get_by(Account, username: username) do
      %Account{} = account ->
        update_json = SukhiFedi.AP.ActorJson.build_update(account)

        Oban.insert!(
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

  defp insert_follow(_), do: :ok

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
      domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")

      Enum.each(to_list, fn recipient_uri ->
        record_participant(conversation_ap_id, recipient_uri)

        # Save note locally if the recipient is a local account
        maybe_save_dm_note(recipient_uri, domain, object, actor_uri, conversation_ap_id)
      end)
    end
  end

  defp maybe_handle_dm(_), do: :ok

  defp record_participant(conversation_ap_id, actor_uri) when is_binary(conversation_ap_id) do
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
    username = actor_uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()
    account = if String.contains?(actor_uri, domain), do: Repo.get_by(Account, username: username), else: nil

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
      account = Repo.get_by(Account, username: username)

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

  # Handle Add/Remove targeting a featured collection (pinned/unpinned posts).
  defp maybe_handle_pin_unpin(%{"type" => "Add", "actor" => actor_uri, "object" => note_uri, "target" => target_uri})
       when is_binary(actor_uri) and is_binary(note_uri) and is_binary(target_uri) do
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
    username = actor_uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()
    account = if String.contains?(actor_uri, domain), do: Repo.get_by(Account, username: username), else: nil

    if account && String.ends_with?(target_uri, "/featured") do
      note = Repo.get_by(SukhiFedi.Schema.Note, ap_id: note_uri)
      if note, do: PinnedNotes.pin(account.id, note.id)
    end
  end

  defp maybe_handle_pin_unpin(%{"type" => "Remove", "actor" => actor_uri, "object" => note_uri, "target" => target_uri})
       when is_binary(actor_uri) and is_binary(note_uri) and is_binary(target_uri) do
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
    username = actor_uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()
    account = if String.contains?(actor_uri, domain), do: Repo.get_by(Account, username: username), else: nil

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
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")

    if String.contains?(uri, domain) do
      username = uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()
      case Repo.get_by(Account, username: username) do
        nil -> nil
        account -> account.id
      end
    end
  end

  defp normalize_collection(list) when is_list(list), do: list
  defp normalize_collection(str) when is_binary(str), do: [str]
  defp normalize_collection(_), do: []
end
