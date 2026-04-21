# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MastodonMedia do
  @moduledoc """
  Mastodon `/api/v1/media`, `/api/v2/media`, `/api/v1/media/:id`.

      POST /api/v1/media       multipart  scope: write:media   sync (200)
      POST /api/v2/media       multipart  scope: write:media   async (202)
      GET  /api/v1/media/:id              scope: read:media
      PUT  /api/v1/media/:id   JSON       scope: write:media

  Inline upload cap: 8 MiB. Larger uploads need a presigned-URL flow,
  which the existing `SukhiFedi.Addons.Media.generate_upload_url/3`
  supports but isn't yet exposed via Mastodon REST.
  """

  use SukhiApi.Capability, addon: :mastodon_api

  alias SukhiApi.{GatewayRpc, Multipart}
  alias SukhiApi.Views.MastodonMedia

  @max_upload_bytes 8 * 1024 * 1024

  @impl true
  def routes do
    [
      {:post, "/api/v1/media", &create/1, scope: "write:media"},
      {:post, "/api/v2/media", &create_v2/1, scope: "write:media"},
      {:get, "/api/v1/media/:id", &show/1, scope: "read:media"},
      {:put, "/api/v1/media/:id", &update/1, scope: "write:media"}
    ]
  end

  # ── POST /api/v1/media (synchronous) ────────────────────────────────────

  def create(req), do: do_create(req, sync: true)

  def create_v2(req), do: do_create(req, sync: false)

  defp do_create(req, sync: sync?) do
    %{current_account: viewer} = req[:assigns]
    ct = content_type(req[:headers] || [])

    cond do
      is_nil(viewer) ->
        ok(403, %{error: "this endpoint requires a user-bound token"})

      not String.starts_with?(ct, "multipart/form-data") ->
        ok(415, %{error: "expected multipart/form-data"})

      true ->
        case Multipart.parse(req[:body] || "", ct, max_file_bytes: @max_upload_bytes) do
          {:ok, %{file: nil}} ->
            ok(422, %{error: "missing file part"})

          {:ok, %{file: file, fields: fields}} ->
            attrs = %{
              "filename" => file.filename,
              "content_type" => file.content_type,
              "description" => fields["description"]
            }

            case GatewayRpc.call(SukhiFedi.Addons.Media, :create_from_upload, [
                   viewer.id,
                   file.bytes,
                   attrs
                 ]) do
              {:ok, {:ok, media}} ->
                status = if sync?, do: 200, else: 202
                ok(status, MastodonMedia.render(media))

              {:ok, {:error, :empty_upload}} ->
                ok(422, %{error: "empty_upload"})

              {:ok, {:error, :file_too_large}} ->
                ok(413, %{error: "file_too_large"})

              {:ok, {:error, {:validation, errors}}} ->
                ok(422, %{error: "validation_failed", details: errors})

              {:ok, {:error, reason}} ->
                ok(422, %{error: inspect(reason)})

              {:error, :not_connected} ->
                ok(503, %{error: "gateway_not_connected"})

              {:error, {:badrpc, r}} ->
                ok(503, %{error: "gateway_rpc_failed", detail: inspect(r)})

              _ ->
                ok(500, %{error: "internal_error"})
            end

          {:error, :file_too_large} ->
            ok(413, %{error: "file_too_large"})

          {:error, reason} ->
            ok(400, %{error: "bad_multipart", detail: to_string(reason)})
        end
    end
  end

  # ── GET /api/v1/media/:id ────────────────────────────────────────────────

  def show(req) do
    %{current_account: viewer} = req[:assigns]
    id = req[:path_params]["id"]

    case viewer do
      nil ->
        ok(403, %{error: "this endpoint requires a user-bound token"})

      %{} = v ->
        case GatewayRpc.call(SukhiFedi.Addons.Media, :get_media, [v.id, id]) do
          {:ok, {:ok, media}} -> ok(200, MastodonMedia.render(media))
          {:ok, {:error, :not_found}} -> ok(404, %{error: "not_found"})
          {:ok, {:error, :forbidden}} -> ok(403, %{error: "forbidden"})
          {:error, :not_connected} -> ok(503, %{error: "gateway_not_connected"})
          {:error, {:badrpc, r}} -> ok(503, %{error: "gateway_rpc_failed", detail: inspect(r)})
          _ -> ok(500, %{error: "internal_error"})
        end
    end
  end

  # ── PUT /api/v1/media/:id ────────────────────────────────────────────────

  def update(req) do
    %{current_account: viewer} = req[:assigns]
    id = req[:path_params]["id"]
    attrs = decode_update_attrs(req)

    case viewer do
      nil ->
        ok(403, %{error: "this endpoint requires a user-bound token"})

      %{} = v ->
        case GatewayRpc.call(SukhiFedi.Addons.Media, :update_media, [v.id, id, attrs]) do
          {:ok, {:ok, media}} -> ok(200, MastodonMedia.render(media))
          {:ok, {:error, :not_found}} -> ok(404, %{error: "not_found"})
          {:ok, {:error, :forbidden}} -> ok(403, %{error: "forbidden"})
          {:ok, {:error, :already_attached}} -> ok(422, %{error: "already_attached"})
          {:ok, {:error, {:validation, errors}}} -> ok(422, %{error: "validation_failed", details: errors})
          {:error, :not_connected} -> ok(503, %{error: "gateway_not_connected"})
          {:error, {:badrpc, r}} -> ok(503, %{error: "gateway_rpc_failed", detail: inspect(r)})
          _ -> ok(500, %{error: "internal_error"})
        end
    end
  end

  defp decode_update_attrs(req) do
    headers = req[:headers] || []
    ct = content_type(headers)

    cond do
      String.contains?(ct, "application/json") ->
        case Jason.decode(req[:body] || "") do
          {:ok, %{} = m} -> m
          _ -> %{}
        end

      String.contains?(ct, "application/x-www-form-urlencoded") ->
        URI.decode_query(req[:body] || "")

      true ->
        %{}
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  defp content_type(headers) do
    Enum.find_value(headers, "", fn {k, v} ->
      if String.downcase(to_string(k)) == "content-type", do: to_string(v), else: nil
    end)
  end

  defp ok(status, body) do
    {:ok,
     %{
       status: status,
       body: Jason.encode!(body),
       headers: [{"content-type", "application/json"}]
     }}
  end
end
