# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.AP.Instructions.Reactions do
  @moduledoc """
  Inbound `Like` (Mastodon favourite) and `EmojiReact` (Misskey custom
  emoji reaction), plus their `Undo`s.
  """

  import Ecto.Query

  alias SukhiFedi.AP.Instructions.{Extract, Resolve}
  alias SukhiFedi.{Notes, Notifications, Repo}
  alias SukhiFedi.Schema.{Account, Note, Reaction}

  @doc """
  Inbound `Like` (Mastodon favourite) or `EmojiReact` (Misskey custom
  emoji reaction) on a note we can resolve → materialise a `reactions`
  row and notify the note's author. The reaction already happened on
  the remote side, so the row is inserted directly: no outbox event,
  because re-broadcasting someone else's reaction would be wrong.
  """
  def maybe_handle_reaction(
        %{"type" => type, "actor" => actor_uri, "object" => object} = activity
      )
      when type in ["Like", "EmojiReact"] and is_binary(actor_uri) do
    with %Note{id: note_id, account_id: author_id} <- Resolve.resolve_target_note(object),
         {:ok, %Account{id: reactor_id}} <- Resolve.resolve_or_ingest_actor(actor_uri) do
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

  def maybe_handle_reaction(_), do: :ok

  @doc "Undo(Like) / Undo(EmojiReact): drop the matching `reactions` row."
  def undo_reaction(actor_uri, inner) do
    with %Note{id: note_id} <- Resolve.resolve_target_note(inner["object"]),
         {:ok, %Account{id: reactor_id}} <- Resolve.resolve_or_ingest_actor(actor_uri) do
      emoji = stored_reaction_emoji(inner, actor_uri)

      from(r in Reaction,
        where: r.account_id == ^reactor_id and r.note_id == ^note_id and r.emoji == ^emoji
      )
      |> Repo.delete_all()
    end

    :ok
  end

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
        domain = Extract.actor_host(actor_uri)
        upsert_emoji_from_activity(content, activity["tag"], domain)
        SukhiFedi.CustomEmojis.namespaced(content, domain)
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
end
