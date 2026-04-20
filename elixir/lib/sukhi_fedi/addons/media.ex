# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addons.Media do
  @moduledoc """
  Media addon — S3/R2 presigned upload URLs and note attachments.

  Required S3 env vars:

    * `S3_BUCKET` (default `"sukhi-media"`)
    * `S3_REGION` (default `"auto"`)
    * `S3_ENDPOINT` — e.g. `https://<account>.r2.cloudflarestorage.com`
    * `S3_ACCESS_KEY`, `S3_SECRET_KEY`
    * `S3_PUBLIC_URL` — CDN URL

  Without these, uploads fall back to local `/uploads/<key>` (useful
  for development, not for production).
  """

  use SukhiFedi.Addon, id: :media

  import Ecto.Query
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Media

  @bucket System.get_env("S3_BUCKET") || "sukhi-media"
  @region System.get_env("S3_REGION") || "auto"
  @endpoint System.get_env("S3_ENDPOINT")
  @access_key System.get_env("S3_ACCESS_KEY")
  @secret_key System.get_env("S3_SECRET_KEY")
  @public_url System.get_env("S3_PUBLIC_URL")

  def generate_upload_url(account_id, filename, _content_type) do
    key =
      "#{account_id}/#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}/#{filename}"

    url = presigned_put_url(key)

    {:ok, %{upload_url: url, key: key, public_url: public_url(key)}}
  end

  def create_media(attrs) do
    %Media{}
    |> Media.changeset(attrs)
    |> Repo.insert()
  end

  def attach_to_note(note_id, media_ids) do
    Repo.insert_all(
      "note_media",
      Enum.map(media_ids, &%{note_id: note_id, media_id: &1}),
      on_conflict: :nothing
    )
  end

  def list_by_account(account_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    Media
    |> where([m], m.account_id == ^account_id)
    |> order_by([m], desc: m.created_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp presigned_put_url(key) do
    if @endpoint && @access_key && @secret_key do
      timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
      date = String.slice(timestamp, 0, 8)

      url = "#{@endpoint}/#{@bucket}/#{key}"

      query =
        "X-Amz-Algorithm=AWS4-HMAC-SHA256" <>
          "&X-Amz-Credential=#{@access_key}%2F#{date}%2F#{@region}%2Fs3%2Faws4_request" <>
          "&X-Amz-Date=#{timestamp}" <>
          "&X-Amz-Expires=900" <>
          "&X-Amz-SignedHeaders=host"

      signature = sign_request("PUT", key, query, timestamp, date)
      "#{url}?#{query}&X-Amz-Signature=#{signature}"
    else
      "/uploads/#{key}"
    end
  end

  defp sign_request(method, key, query, timestamp, date) do
    host = URI.parse(@endpoint).host

    canonical_request =
      "#{method}\n/#{@bucket}/#{key}\n#{query}\nhost:#{host}\n\nhost\nUNSIGNED-PAYLOAD"

    string_to_sign =
      "AWS4-HMAC-SHA256\n#{timestamp}\n#{date}/#{@region}/s3/aws4_request\n" <>
        (:crypto.hash(:sha256, canonical_request) |> Base.encode16(case: :lower))

    signing_key =
      hmac("AWS4#{@secret_key}", date)
      |> hmac(@region)
      |> hmac("s3")
      |> hmac("aws4_request")

    hmac(signing_key, string_to_sign) |> Base.encode16(case: :lower)
  end

  defp hmac(key, data), do: :crypto.mac(:hmac, :sha256, key, data)

  defp public_url(key) do
    if @public_url do
      "#{@public_url}/#{key}"
    else
      "#{@endpoint}/#{@bucket}/#{key}"
    end
  end
end
