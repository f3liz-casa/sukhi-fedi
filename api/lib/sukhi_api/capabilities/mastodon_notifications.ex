# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MastodonNotifications do
  @moduledoc """
  Mastodon notifications surface.

      GET    /api/v1/notifications              read:notifications
      GET    /api/v1/notifications/:id          read:notifications
      POST   /api/v1/notifications/clear        write:notifications
      POST   /api/v1/notifications/:id/dismiss  write:notifications

  Index supports the usual `max_id` / `since_id` / `min_id` / `limit`
  paging plus Mastodon's `types[]` and `exclude_types[]` filters.
  """

  use SukhiApi.Capability, addon: :mastodon_api

  alias SukhiApi.{GatewayRpc, Pagination}
  alias SukhiApi.Views.MastodonNotification

  @impl true
  def routes do
    [
      {:get, "/api/v1/notifications", &index/1, scope: "read:notifications"},
      {:get, "/api/v1/notifications/:id", &show/1, scope: "read:notifications"},
      {:post, "/api/v1/notifications/clear", &clear/1, scope: "write:notifications"},
      {:post, "/api/v1/notifications/:id/dismiss", &dismiss/1, scope: "write:notifications"}
    ]
  end

  def index(req) do
    %{current_account: viewer} = req[:assigns]

    case viewer do
      nil ->
        ok(403, %{error: "this endpoint requires a user-bound token"})

      %{} = v ->
        opts = parse_opts(req[:query])

        case GatewayRpc.call(SukhiFedi.Notifications, :list, [v.id, Map.to_list(opts)]) do
          {:ok, notifs} when is_list(notifs) ->
            body = MastodonNotification.render_list(notifs)
            headers = [{"content-type", "application/json"}]

            headers =
              case Pagination.link_header("/api/v1/notifications", notifs, & &1.id, opts) do
                nil -> headers
                link -> [link | headers]
              end

            {:ok, %{status: 200, body: JSON.encode!(body), headers: headers}}

          {:error, reason} ->
            rpc_error(reason)

          _ ->
            ok(500, %{error: "internal_error"})
        end
    end
  end

  def show(req) do
    %{current_account: viewer} = req[:assigns]
    id = req[:path_params]["id"]

    case viewer do
      nil ->
        ok(403, %{error: "this endpoint requires a user-bound token"})

      %{} = v ->
        case GatewayRpc.call(SukhiFedi.Notifications, :get, [v.id, id]) do
          {:ok, nil} -> ok(404, %{error: "not_found"})
          {:ok, notif} -> ok(200, MastodonNotification.render(notif))
          {:error, reason} -> rpc_error(reason)
          _ -> ok(500, %{error: "internal_error"})
        end
    end
  end

  def clear(req), do: scoped_action(req, :clear, [])
  def dismiss(req), do: scoped_action(req, :dismiss, [req[:path_params]["id"]])

  defp scoped_action(req, fun, extra_args) do
    %{current_account: viewer} = req[:assigns]

    case viewer do
      nil ->
        ok(403, %{error: "this endpoint requires a user-bound token"})

      %{} = v ->
        case GatewayRpc.call(SukhiFedi.Notifications, fun, [v.id | extra_args]) do
          {:ok, :ok} -> ok(200, %{})
          {:error, reason} -> rpc_error(reason)
          _ -> ok(500, %{error: "internal_error"})
        end
    end
  end

  defp parse_opts(query) do
    base = Pagination.parse_opts(query)
    q = decode_query(query)

    base
    |> maybe_put_list(:types, q["types[]"] || q["types"])
    |> maybe_put_list(:exclude_types, q["exclude_types[]"] || q["exclude_types"])
  end

  # `URI.decode_query/1` keeps only the last value of a repeated key,
  # but Mastodon clients send list filters as `types[]=a&types[]=b` —
  # walk the pairs ourselves and collect repeats into lists, in order.
  defp decode_query(nil), do: %{}
  defp decode_query(""), do: %{}

  defp decode_query(s) when is_binary(s) do
    s
    |> URI.query_decoder()
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      Map.update(acc, k, v, fn
        prev when is_list(prev) -> prev ++ [v]
        prev -> [prev, v]
      end)
    end)
  end

  defp maybe_put_list(opts, _key, nil), do: opts
  defp maybe_put_list(opts, key, v) when is_list(v), do: Map.put(opts, key, v)
  defp maybe_put_list(opts, key, v) when is_binary(v), do: Map.put(opts, key, [v])

  defp rpc_error(:not_connected), do: ok(503, %{error: "gateway_not_connected"})

  defp rpc_error({:badrpc, r}),
    do: ok(503, %{error: "gateway_rpc_failed", detail: inspect(r)})

  defp rpc_error(_), do: ok(500, %{error: "internal_error"})

  defp ok(status, body) do
    {:ok,
     %{
       status: status,
       body: JSON.encode!(body),
       headers: [{"content-type", "application/json"}]
     }}
  end
end
