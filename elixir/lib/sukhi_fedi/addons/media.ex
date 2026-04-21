# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addons.Media do
  @moduledoc """
  Media addon — server-side multipart uploads and presigned URL
  generation. Two upload modes:

  * **Server-side (Mastodon `POST /api/v1/media`)** —
    `create_from_upload/3` accepts the file bytes already received by
    the api plugin node, writes them to local storage (or S3 in
    future), and inserts a `Media` row.

  * **Presigned client-direct upload** — `generate_upload_url/3`
    returns an S3 PUT URL the client uses directly. Not exposed via
    the Mastodon REST surface yet (Mastodon clients always POST bytes
    to the server); kept here for future use.

  Required env for S3 presigned mode:

    * `S3_BUCKET` (default `"sukhi-media"`)
    * `S3_REGION` (default `"auto"`)
    * `S3_ENDPOINT` — e.g. `https://<account>.r2.cloudflarestorage.com`
    * `S3_ACCESS_KEY`, `S3_SECRET_KEY`
    * `S3_PUBLIC_URL` — CDN URL

  For server-side uploads, files land under `MEDIA_DIR` (default
  `priv/static/uploads`) and are served via `Plug.Static` from the
  gateway.
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

  @max_inline_bytes 8 * 1024 * 1024

  # ── server-side upload ───────────────────────────────────────────────────

  @doc """
  Persist an uploaded file. `file_bytes` must already be in memory on
  the gateway (the api plugin node forwards it via `:rpc`). Caps the
  inline size at #{@max_inline_bytes} bytes to keep distributed Erlang
  happy; larger uploads need the presigned-URL flow (deferred).

  Attrs map can carry `description`, `filename`, `content_type`.
  """
  @spec create_from_upload(integer(), binary(), map()) ::
          {:ok, Media.t()} | {:error, atom() | {:validation, map()}}
  def create_from_upload(account_id, file_bytes, attrs)
      when is_integer(account_id) and is_binary(file_bytes) and is_map(attrs) do
    cond do
      byte_size(file_bytes) == 0 ->
        {:error, :empty_upload}

      byte_size(file_bytes) > @max_inline_bytes ->
        {:error, :file_too_large}

      true ->
        do_create_from_upload(account_id, file_bytes, attrs)
    end
  end

  defp do_create_from_upload(account_id, file_bytes, attrs) do
    filename = Map.get(attrs, "filename") || Map.get(attrs, :filename) || "upload.bin"
    content_type = Map.get(attrs, "content_type") || Map.get(attrs, :content_type) || "application/octet-stream"
    description = Map.get(attrs, "description") || Map.get(attrs, :description)

    type = type_for(content_type)
    ext = Path.extname(filename)
    key = "#{account_id}/#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}#{ext}"

    case persist_bytes(key, file_bytes) do
      {:ok, url} ->
        %Media{}
        |> Media.changeset(%{
          url: url,
          type: type,
          description: description,
          size: byte_size(file_bytes),
          account_id: account_id
        })
        |> Repo.insert()
        |> case do
          {:ok, media} -> {:ok, media}
          {:error, %Ecto.Changeset{} = cs} -> {:error, {:validation, changeset_errors(cs)}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist_bytes(key, bytes) do
    dir = media_dir()
    full_path = Path.join(dir, key)

    with :ok <- File.mkdir_p(Path.dirname(full_path)),
         :ok <- File.write(full_path, bytes) do
      {:ok, public_local_url(key)}
    else
      _ -> {:error, :write_failed}
    end
  end

  defp media_dir do
    System.get_env("MEDIA_DIR") || Path.join([:code.priv_dir(:sukhi_fedi), "static", "uploads"])
  end

  defp public_local_url(key) do
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
    scheme = if domain in ["localhost", "localhost:4000"] or String.starts_with?(domain, "localhost"), do: "http", else: "https"
    "#{scheme}://#{domain}/uploads/#{key}"
  end

  defp type_for("image/" <> _), do: "image"
  defp type_for("video/" <> _), do: "video"
  defp type_for("audio/" <> _), do: "audio"
  defp type_for(_), do: "unknown"

  # ── reads ────────────────────────────────────────────────────────────────

  @doc "Owner-scoped read. `:not_found` if the media doesn't exist OR isn't owned by the caller."
  @spec get_media(integer(), integer() | binary()) ::
          {:ok, Media.t()} | {:error, :not_found | :forbidden}
  def get_media(account_id, media_id) when is_integer(account_id) do
    case parse_int(media_id) do
      nil ->
        {:error, :not_found}

      id ->
        case Repo.get(Media, id) do
          nil -> {:error, :not_found}
          %Media{account_id: ^account_id} = m -> {:ok, m}
          %Media{} -> {:error, :forbidden}
        end
    end
  end

  # ── update ──────────────────────────────────────────────────────────────

  @doc """
  Update description / tags. Only allowed while the Media row is
  unattached (i.e. `attached_at IS NULL`). Returns
  `{:error, :already_attached}` once a Note has incorporated it.
  """
  @spec update_media(integer(), integer() | binary(), map()) ::
          {:ok, Media.t()}
          | {:error, :not_found | :forbidden | :already_attached | {:validation, map()}}
  def update_media(account_id, media_id, attrs) when is_integer(account_id) do
    case get_media(account_id, media_id) do
      {:error, e} ->
        {:error, e}

      {:ok, %Media{attached_at: %DateTime{}}} ->
        {:error, :already_attached}

      {:ok, %Media{} = m} ->
        m
        |> Media.changeset_update(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, updated}
          {:error, %Ecto.Changeset{} = cs} -> {:error, {:validation, changeset_errors(cs)}}
        end
    end
  end

  # ── existing presigned-URL surface ───────────────────────────────────────

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

  @doc """
  Attach Media rows to a Note. Stamps `attached_at` so subsequent
  `update_media/3` calls reject changes (Mastodon contract).
  """
  def attach_to_note(note_id, media_ids) do
    Repo.insert_all(
      "note_media",
      Enum.map(media_ids, &%{note_id: note_id, media_id: &1}),
      on_conflict: :nothing
    )

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.update_all(
      from(m in Media, where: m.id in ^media_ids and is_nil(m.attached_at)),
      set: [attached_at: now]
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

  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp changeset_errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end
end
