# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.AP.MediaSerialize do
  @moduledoc """
  Outbound counterpart to `SukhiFedi.AP.MediaIngest`: turn local `Media`
  rows into AP `attachment` objects so our posts carry their images /
  video / audio when they federate out.

  Two shapes, same fields:

    * `descriptor/1` — a JSON-safe plain map for the `sns.outbox.*` event
      payload. The delivery node forwards it to the bun `note` / `dm`
      translator, which injects it as the Note's `attachment`.
    * `ap_attachment/1` — the AP `Document` object the gateway emits
      directly when a remote server dereferences a note (NoteController)
      or pages the outbox (CollectionController).

  Mirrors the field set `MediaIngest.attrs/2` reads on the way in
  (`url`, `mediaType`, `name`, `blurhash`, `width`, `height`) so a note
  that round-trips through another server and back keeps its media.
  """

  alias SukhiFedi.Schema.Media

  @doc "Plain-map descriptors for the outbox event payload, in `media_ids` order."
  @spec descriptors([Media.t()]) :: [map()]
  def descriptors(media) when is_list(media), do: Enum.map(media, &descriptor/1)

  @spec descriptor(Media.t()) :: map()
  def descriptor(%Media{} = m) do
    %{
      "url" => m.url,
      "mediaType" => media_type(m),
      "name" => m.description,
      "blurhash" => m.blurhash,
      "width" => m.width,
      "height" => m.height
    }
    |> drop_nils()
  end

  @doc "AP `Document` attachment objects for direct gateway-served AP JSON."
  @spec ap_attachments([Media.t()]) :: [map()]
  def ap_attachments(media) when is_list(media), do: Enum.map(media, &ap_attachment/1)

  @spec ap_attachment(Media.t()) :: map()
  def ap_attachment(%Media{} = m) do
    descriptor(m) |> Map.put("type", "Document")
  end

  # `Media.type` is the coarse class ("image"/"video"/...), not a real
  # MIME. Outbound media is always a local upload, whose key keeps the
  # original extension, so reconstruct the precise `mediaType` from the
  # URL — same mapping the upload proxy (router `serve_upload`) serves
  # bytes with. Unknown extension → omit `mediaType` and let the
  # receiver sniff.
  defp media_type(%Media{url: url}) when is_binary(url) do
    case url |> Path.extname() |> String.downcase() do
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".avif" -> "image/avif"
      ".mp4" -> "video/mp4"
      ".webm" -> "video/webm"
      ".mov" -> "video/quicktime"
      ".mp3" -> "audio/mpeg"
      ".ogg" -> "audio/ogg"
      ".m4a" -> "audio/mp4"
      _ -> nil
    end
  end

  defp media_type(_), do: nil

  defp drop_nils(map), do: :maps.filter(fn _k, v -> not is_nil(v) end, map)
end
