# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.StatusHydration do
  @moduledoc """
  Render notes into Mastodon Status JSON with the per-note context that
  has to be batch-fetched from the gateway — chiefly the Sukhi reaction
  chips (`reactions_for_notes`).

  Every status-returning endpoint should render through here. The view
  itself only shows reactions when they're handed in via the render
  context, so any path that calls `MastodonStatus.render/1` bare drops
  them silently — which is how the note page and profile lost their
  reaction chips while the timeline kept them. Funnelling the hydration
  here keeps the timeline, the profile, the note page and its thread in
  step instead of each capability re-deriving (and drifting on) the
  context.
  """

  alias SukhiApi.GatewayRpc
  alias SukhiApi.Views.MastodonStatus

  @doc "Render one note (or nil) with reaction chips from `viewer`'s view."
  @spec one(map() | nil, map() | nil) :: map() | nil
  def one(nil, _viewer), do: nil
  def one(note, viewer), do: [note] |> many(viewer) |> hd()

  @doc "Render a list of notes with reaction chips from `viewer`'s view."
  @spec many([map()], map() | nil) :: [map()]
  def many([], _viewer), do: []

  def many(notes, viewer) when is_list(notes) do
    note_ids = Enum.map(notes, & &1.id)
    viewer_id = viewer && viewer.id

    reactions =
      case GatewayRpc.call(SukhiFedi.Notes, :reactions_for_notes, [note_ids, viewer_id]) do
        {:ok, m} when is_map(m) -> m
        _ -> %{}
      end

    MastodonStatus.render_list(notes, %{}, %{}, reactions)
  end
end
