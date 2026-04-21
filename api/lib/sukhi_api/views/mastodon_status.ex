# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Views.MastodonStatus do
  @moduledoc """
  Render a `Note` (or hydrated map) into Mastodon Status JSON.

  Counts and viewer-context flags are passed in via the second
  argument:

      MastodonStatus.render(note, %{
        counts: %{replies: int, reblogs: int, favourites: int},
        viewer: %{favourited: bool, reblogged: bool, bookmarked: bool, pinned: bool}
      })

  Both keys are optional; missing fields default to `0` / `false`.
  Capabilities should batch-fetch counts/viewer flags via
  `SukhiFedi.Notes.{counts_for_notes, viewer_flags_many}` and pass
  the per-note submap on render.
  """

  alias SukhiApi.Views.{Id, MastodonAccount, MastodonMedia}

  @spec render(map() | nil, map()) :: map() | nil
  def render(note, ctx \\ %{})
  def render(nil, _ctx), do: nil

  def render(note, ctx) do
    counts = Map.get(ctx, :counts, %{})
    viewer = Map.get(ctx, :viewer, %{})

    %{
      id: Id.encode(note.id),
      created_at: format_dt(Map.get(note, :created_at)),
      in_reply_to_id: nil,
      in_reply_to_account_id: nil,
      sensitive: !!(Map.get(note, :cw) && Map.get(note, :cw) != ""),
      spoiler_text: Map.get(note, :cw) || "",
      visibility: Map.get(note, :visibility) || "public",
      language: nil,
      uri: Map.get(note, :ap_id),
      url: Map.get(note, :ap_id),
      replies_count: Map.get(counts, :replies, 0),
      reblogs_count: Map.get(counts, :reblogs, 0),
      favourites_count: Map.get(counts, :favourites, 0),
      edited_at: nil,
      content: render_content(note),
      reblog: nil,
      application: nil,
      account: render_account(note),
      media_attachments: render_media(note),
      mentions: [],
      tags: [],
      emojis: [],
      card: nil,
      poll: nil,
      pinned: Map.get(viewer, :pinned, false),
      bookmarked: Map.get(viewer, :bookmarked, false),
      favourited: Map.get(viewer, :favourited, false),
      reblogged: Map.get(viewer, :reblogged, false),
      muted: false
    }
  end

  @doc """
  Render a list of notes, looking up per-note counts/viewer-flags
  from the supplied maps (each keyed by note id).
  """
  @spec render_list([map()], map(), map()) :: [map()]
  def render_list(notes, counts_by_id \\ %{}, viewer_by_id \\ %{}) when is_list(notes) do
    Enum.map(notes, fn n ->
      render(n, %{
        counts: Map.get(counts_by_id, n.id, %{}),
        viewer: Map.get(viewer_by_id, n.id, %{})
      })
    end)
  end

  defp render_content(note) do
    raw = Map.get(note, :content) || ""
    if String.starts_with?(raw, "<"), do: raw, else: "<p>#{raw}</p>"
  end

  defp render_account(note) do
    account = Map.get(note, :account)

    if is_map(account) and Map.has_key?(account, :username) do
      MastodonAccount.render(account, %{})
    else
      nil
    end
  end

  defp render_media(note) do
    case Map.get(note, :media) do
      media when is_list(media) -> Enum.map(media, &MastodonMedia.render/1)
      _ -> []
    end
  end

  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(_), do: nil
end
