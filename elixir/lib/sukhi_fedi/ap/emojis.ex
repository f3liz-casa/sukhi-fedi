# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.AP.Emojis do
  @moduledoc """
  Turn an ActivityPub `tag` array into the Mastodon `emojis` shape.

  Both Misskey and Mastodon advertise the custom emoji used in an
  actor's name/bio or a note's content as `Emoji` entries in `tag`:

      {"type": "Emoji", "name": ":blobcat:",
       "icon": {"type": "Image", "url": "https://…/blobcat.png"}}

  We store the rendered list on the row (`accounts.emojis` /
  `notes.emojis`) so the Mastodon view can echo it verbatim and clients
  swap `:blobcat:` for the image. `shortcode` is the bare name (no
  colons) so it matches the text; `static_url` falls back to `url` when
  the peer doesn't offer a separate still frame.

  Some peers list the same emoji once per occurrence (name + bio both
  wearing `:skeb:` gives two entries), so the list is deduplicated by
  shortcode — first entry wins.
  """

  @spec from_tag(term()) :: [map()]
  def from_tag(tag) when is_list(tag),
    do: tag |> Enum.flat_map(&one/1) |> Enum.uniq_by(& &1["shortcode"])
  def from_tag(_), do: []

  defp one(%{"type" => "Emoji", "name" => name} = entry) when is_binary(name) and name != "" do
    case icon_url(entry["icon"]) do
      nil ->
        []

      url ->
        [
          %{
            "shortcode" => String.trim(name, ":"),
            "url" => url,
            "static_url" => url,
            "visible_in_picker" => false
          }
        ]
    end
  end

  defp one(_), do: []

  defp icon_url(%{"url" => url}) when is_binary(url), do: url
  defp icon_url(url) when is_binary(url), do: url
  defp icon_url(_), do: nil
end
