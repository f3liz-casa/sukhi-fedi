# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.AP.MediaIngest do
  @moduledoc """
  Turn an inbound AP object's `attachment` into local `Media` rows linked
  to a note, so remote posts render their images / video / audio.

  We point at the remote URL directly — same as avatars and custom emoji,
  no re-hosting. Shared by every remote-note ingest path (inbound
  `Create`, DMs, on-demand `NoteFetcher`) and by the archive backfill, so
  the parsing lives in one place.

  `attach/3` is idempotent: it does nothing when the note already has
  media, so re-delivery and a re-run of the backfill won't duplicate.
  """

  import Ecto.Query

  alias SukhiFedi.Addons.Media
  alias SukhiFedi.Repo

  @doc """
  Attach the AP `attachment` of an object to `note_id`, authored by
  `account_id`. Accepts a list, a single object, or nil. No-op when the
  note already has media. Best-effort: a malformed item is skipped, not
  fatal. Returns `:ok`.
  """
  @spec attach(integer(), integer(), term()) :: :ok
  def attach(note_id, account_id, %{} = one), do: attach(note_id, account_id, [one])

  def attach(note_id, account_id, attachments)
      when is_list(attachments) and is_integer(note_id) and is_integer(account_id) do
    if attachments != [] and not has_media?(note_id) do
      media_ids =
        Enum.flat_map(attachments, fn att ->
          with %{} = attrs <- attrs(att, account_id),
               {:ok, %{id: id}} <- Media.create_media(attrs) do
            [id]
          else
            _ -> []
          end
        end)

      if media_ids != [], do: Media.attach_to_note(note_id, media_ids)
    end

    :ok
  end

  def attach(_note_id, _account_id, _), do: :ok

  @doc "True when the note already has at least one media row linked."
  @spec has_media?(integer()) :: boolean()
  def has_media?(note_id) do
    Repo.exists?(from(nm in "note_media", where: nm.note_id == ^note_id))
  end

  defp attrs(%{} = att, account_id) do
    with url when is_binary(url) <- extract_url(att["url"]),
         type when is_binary(type) <- media_type(att["mediaType"]) do
      %{
        "account_id" => account_id,
        "url" => url,
        "remote_url" => url,
        "type" => type,
        "description" => att["name"] || att["summary"],
        "blurhash" => att["blurhash"],
        "width" => att["width"],
        "height" => att["height"]
      }
    else
      _ -> nil
    end
  end

  defp attrs(_, _), do: nil

  # AP `url` may be a string, a Link object (`%{"href" => ...}`), or a
  # list of either (content negotiation). Take the first usable href.
  defp extract_url(url) when is_binary(url), do: url
  defp extract_url(%{"href" => href}) when is_binary(href), do: href
  defp extract_url([first | _]), do: extract_url(first)
  defp extract_url(_), do: nil

  defp media_type("image/" <> _), do: "image"
  defp media_type("video/" <> _), do: "video"
  defp media_type("audio/" <> _), do: "audio"
  defp media_type(_), do: nil
end
