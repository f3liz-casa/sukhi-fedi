# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Views.MastodonMedia do
  @moduledoc """
  Render a `Media` row into Mastodon MediaAttachment JSON.

  PR3 ships the read-side renderer (used by `MastodonStatus`); PR4
  ships the upload capability that produces these rows.
  """

  alias SukhiApi.Views.Id

  @spec render(map()) :: map()
  def render(media) do
    %{
      id: Id.encode(media.id),
      type: Map.get(media, :type) || "unknown",
      url: Map.get(media, :url),
      preview_url: Map.get(media, :url),
      remote_url: Map.get(media, :remote_url),
      text_url: nil,
      meta: meta(media),
      description: Map.get(media, :description),
      blurhash: Map.get(media, :blurhash)
    }
  end

  defp meta(media) do
    base = %{}

    base =
      case {Map.get(media, :width), Map.get(media, :height)} do
        {w, h} when is_integer(w) and is_integer(h) ->
          Map.put(base, :original, %{width: w, height: h, size: "#{w}x#{h}", aspect: w / h})

        _ ->
          base
      end

    base
  end
end
