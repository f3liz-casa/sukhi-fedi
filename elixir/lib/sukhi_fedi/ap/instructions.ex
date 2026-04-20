# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.AP.Instructions do
  @moduledoc """
  Parses and executes instructions returned by Deno workers.
  """

  alias SukhiFedi.Delivery.Worker
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Follow, Object, ConversationParticipant, Account}
  alias SukhiFedi.Relays
  alias SukhiFedi.Addons.PinnedNotes

  @public_ns "https://www.w3.org/ns/activitystreams#Public"
  @as_public "Public"

  @doc """
  Executes an instruction map returned from the ap.inbox NATS topic.
  """
  @spec execute(map()) :: :ok
  def execute(%{"action" => "save", "object" => object_data}) do
    insert_object(object_data)
    maybe_handle_dm(object_data)
    maybe_handle_relay_accept(object_data)
    maybe_handle_pin_unpin(object_data)
    :ok
  end

  def execute(%{"action" => "save_and_reply", "save" => save_data, "reply" => reply, "inbox" => inbox_url}) do
    insert_follow(save_data)

    followee_uri = save_data["followeeUri"]

    %{raw_json: reply, inbox_url: inbox_url, actor_uri: followee_uri}
    |> Worker.new()
    |> Oban.insert!()

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
      follower_uri = follow_data["actor"]

      %Follow{
        follower_uri: follower_uri,
        followee_id: account.id,
        state: "accepted"
      }
      |> Repo.insert(on_conflict: :nothing)
    end
  end

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

  defp normalize_collection(list) when is_list(list), do: list
  defp normalize_collection(str) when is_binary(str), do: [str]
  defp normalize_collection(_), do: []
end
