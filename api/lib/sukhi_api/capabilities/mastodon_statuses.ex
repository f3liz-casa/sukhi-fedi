# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MastodonStatuses do
  @moduledoc """
  Mastodon `/api/v1/statuses/*` capability.

      POST   /api/v1/statuses              scope: write:statuses
      GET    /api/v1/statuses/:id          (public)
      DELETE /api/v1/statuses/:id          scope: write:statuses
      GET    /api/v1/statuses/:id/context  (public)

  Note attaching media via `media_ids[]` reuses PR4's
  `SukhiFedi.Addons.Media.attach_to_note/2` indirectly via
  `SukhiFedi.Notes.create_status/2`'s `Multi`. Until PR4 ships the
  upload side, callers must already hold valid Media ids in the DB.
  """

  use SukhiApi.Capability, addon: :mastodon_api

  alias SukhiApi.GatewayRpc
  alias SukhiApi.Views.MastodonStatus

  @impl true
  def routes do
    [
      {:post, "/api/v1/statuses", &create/1, scope: "write:statuses"},
      {:get, "/api/v1/statuses/:id", &show/1},
      {:delete, "/api/v1/statuses/:id", &delete/1, scope: "write:statuses"},
      {:get, "/api/v1/statuses/:id/context", &context/1}
    ]
  end

  # ── POST /api/v1/statuses ────────────────────────────────────────────────

  def create(req) do
    %{current_account: viewer} = req[:assigns]

    case viewer do
      nil ->
        ok(403, %{error: "this endpoint requires a user-bound token"})

      %{} = v ->
        attrs = decode_status_attrs(req)

        case GatewayRpc.call(SukhiFedi.Notes, :create_status, [v, attrs]) do
          {:ok, {:ok, note}} ->
            ok(200, MastodonStatus.render(note))

          {:ok, {:error, {:validation, errors}}} ->
            ok(422, %{error: "validation_failed", details: errors})

          {:ok, {:error, :media_not_owned}} ->
            ok(422, %{error: "media_not_owned"})

          {:ok, {:error, :direct_visibility_not_supported}} ->
            ok(422, %{error: "direct_visibility_not_supported"})

          {:ok, {:error, reason}} ->
            ok(422, %{error: inspect(reason)})

          {:error, :not_connected} ->
            ok(503, %{error: "gateway_not_connected"})

          {:error, {:badrpc, r}} ->
            ok(503, %{error: "gateway_rpc_failed", detail: inspect(r)})

          _ ->
            ok(500, %{error: "internal_error"})
        end
    end
  end

  defp decode_status_attrs(req) do
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
        |> normalize_form_arrays()

      true ->
        %{}
    end
  end

  # Mastodon clients send media_ids[]=1&media_ids[]=2; URI.decode_query
  # returns the LAST one as a single value. Re-collect.
  defp normalize_form_arrays(map) do
    map
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      case String.replace_suffix(k, "[]", "") do
        ^k -> Map.put(acc, k, v)
        base -> Map.update(acc, base, [v], fn existing -> List.wrap(existing) ++ [v] end)
      end
    end)
  end

  # ── GET /api/v1/statuses/:id ─────────────────────────────────────────────

  def show(req) do
    id = req[:path_params]["id"]

    case GatewayRpc.call(SukhiFedi.Notes, :get_note, [id]) do
      {:ok, {:ok, note}} -> ok(200, MastodonStatus.render(note))
      {:ok, {:error, :not_found}} -> ok(404, %{error: "not_found"})
      {:error, :not_connected} -> ok(503, %{error: "gateway_not_connected"})
      {:error, {:badrpc, r}} -> ok(503, %{error: "gateway_rpc_failed", detail: inspect(r)})
      _ -> ok(500, %{error: "internal_error"})
    end
  end

  # ── DELETE /api/v1/statuses/:id ──────────────────────────────────────────

  def delete(req) do
    %{current_account: viewer} = req[:assigns]
    id = req[:path_params]["id"]

    case viewer do
      nil ->
        ok(403, %{error: "this endpoint requires a user-bound token"})

      %{} = v ->
        case GatewayRpc.call(SukhiFedi.Notes, :delete_note, [v, id]) do
          {:ok, {:ok, note}} ->
            # Mastodon quirk: returns the deleted status's last form
            ok(200, MastodonStatus.render(note))

          {:ok, {:error, :not_found}} ->
            ok(404, %{error: "not_found"})

          {:ok, {:error, :forbidden}} ->
            ok(403, %{error: "forbidden"})

          {:error, :not_connected} ->
            ok(503, %{error: "gateway_not_connected"})

          {:error, {:badrpc, r}} ->
            ok(503, %{error: "gateway_rpc_failed", detail: inspect(r)})

          _ ->
            ok(500, %{error: "internal_error"})
        end
    end
  end

  # ── GET /api/v1/statuses/:id/context ─────────────────────────────────────

  def context(req) do
    id = req[:path_params]["id"]

    case GatewayRpc.call(SukhiFedi.Notes, :context, [id]) do
      {:ok, {:ok, %{ancestors: a, descendants: d}}} ->
        ok(200, %{
          ancestors: Enum.map(a, &MastodonStatus.render/1),
          descendants: Enum.map(d, &MastodonStatus.render/1)
        })

      {:ok, {:error, :not_found}} ->
        ok(404, %{error: "not_found"})

      {:error, :not_connected} ->
        ok(503, %{error: "gateway_not_connected"})

      {:error, {:badrpc, r}} ->
        ok(503, %{error: "gateway_rpc_failed", detail: inspect(r)})

      _ ->
        ok(500, %{error: "internal_error"})
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
