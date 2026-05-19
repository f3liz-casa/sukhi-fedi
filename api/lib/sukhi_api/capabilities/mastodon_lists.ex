# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MastodonLists do
  @moduledoc """
  Mastodon lists surface.

      GET    /api/v1/lists                      read:lists
      POST   /api/v1/lists                      write:lists
      GET    /api/v1/lists/:id                  read:lists
      PUT    /api/v1/lists/:id                  write:lists
      DELETE /api/v1/lists/:id                  write:lists
      GET    /api/v1/lists/:id/accounts         read:lists
      POST   /api/v1/lists/:id/accounts         write:lists
      DELETE /api/v1/lists/:id/accounts         write:lists

      GET    /api/v1/timelines/list/:list_id    read:lists
  """

  use SukhiApi.Capability, addon: :mastodon_api

  alias SukhiApi.{GatewayRpc, Pagination}
  alias SukhiApi.Views.{MastodonAccount, MastodonList, MastodonStatus}

  @impl true
  def routes do
    [
      {:get, "/api/v1/lists", &index/1, scope: "read:lists"},
      {:post, "/api/v1/lists", &create/1, scope: "write:lists"},
      {:get, "/api/v1/lists/:id", &show/1, scope: "read:lists"},
      {:put, "/api/v1/lists/:id", &update/1, scope: "write:lists"},
      {:delete, "/api/v1/lists/:id", &delete/1, scope: "write:lists"},
      {:get, "/api/v1/lists/:id/accounts", &accounts/1, scope: "read:lists"},
      {:post, "/api/v1/lists/:id/accounts", &add_accounts/1, scope: "write:lists"},
      {:delete, "/api/v1/lists/:id/accounts", &remove_accounts/1, scope: "write:lists"},
      {:get, "/api/v1/timelines/list/:list_id", &timeline/1, scope: "read:lists"}
    ]
  end

  def index(req) do
    with_viewer(req, fn v ->
      case GatewayRpc.call(SukhiFedi.Lists, :list_for, [v.id]) do
        {:ok, lists} when is_list(lists) -> ok(200, MastodonList.render_list(lists))
        e -> rpc_error(e)
      end
    end)
  end

  def show(req) do
    with_viewer(req, fn v ->
      case GatewayRpc.call(SukhiFedi.Lists, :get, [v.id, req[:path_params]["id"]]) do
        {:ok, {:ok, list}} -> ok(200, MastodonList.render(list))
        {:ok, {:error, :not_found}} -> ok(404, %{error: "not_found"})
        e -> rpc_error(e)
      end
    end)
  end

  def create(req) do
    with_viewer(req, fn v ->
      body = decode_body(req)
      title = body["title"]
      replies_policy = body["replies_policy"]
      exclusive = body["exclusive"]

      attrs =
        %{title: title}
        |> Map.merge(if replies_policy, do: %{replies_policy: replies_policy}, else: %{})
        |> Map.merge(if is_boolean(exclusive), do: %{exclusive: exclusive}, else: %{})

      case GatewayRpc.call(SukhiFedi.Lists, :create, [v.id, attrs]) do
        {:ok, {:ok, list}} -> ok(200, MastodonList.render(list))
        {:ok, {:error, %{} = cs}} -> ok(422, %{error: "validation_failed", detail: cs_errors(cs)})
        e -> rpc_error(e)
      end
    end)
  end

  def update(req) do
    with_viewer(req, fn v ->
      body = decode_body(req)
      id = req[:path_params]["id"]

      case GatewayRpc.call(SukhiFedi.Lists, :update, [v.id, id, body]) do
        {:ok, {:ok, list}} -> ok(200, MastodonList.render(list))
        {:ok, {:error, :not_found}} -> ok(404, %{error: "not_found"})
        {:ok, {:error, %{} = cs}} -> ok(422, %{error: "validation_failed", detail: cs_errors(cs)})
        e -> rpc_error(e)
      end
    end)
  end

  def delete(req) do
    with_viewer(req, fn v ->
      case GatewayRpc.call(SukhiFedi.Lists, :delete, [v.id, req[:path_params]["id"]]) do
        {:ok, {:ok, _}} -> ok(200, %{})
        {:ok, {:error, :not_found}} -> ok(404, %{error: "not_found"})
        e -> rpc_error(e)
      end
    end)
  end

  def accounts(req) do
    with_viewer(req, fn v ->
      case GatewayRpc.call(SukhiFedi.Lists, :list_accounts, [v.id, req[:path_params]["id"]]) do
        {:ok, {:ok, accounts}} ->
          ok(200, Enum.map(accounts, &MastodonAccount.render(&1, %{})))

        {:ok, {:error, :not_found}} ->
          ok(404, %{error: "not_found"})

        e ->
          rpc_error(e)
      end
    end)
  end

  def add_accounts(req), do: membership_op(req, :add_accounts)
  def remove_accounts(req), do: membership_op(req, :remove_accounts)

  defp membership_op(req, fun) do
    with_viewer(req, fn v ->
      body = decode_body(req)
      ids = body["account_ids"] || body["account_ids[]"] || []
      ids = List.wrap(ids)

      case GatewayRpc.call(SukhiFedi.Lists, fun, [v.id, req[:path_params]["id"], ids]) do
        {:ok, :ok} -> ok(200, %{})
        {:ok, {:error, :not_found}} -> ok(404, %{error: "not_found"})
        e -> rpc_error(e)
      end
    end)
  end

  def timeline(req) do
    with_viewer(req, fn v ->
      opts = Pagination.parse_opts(req[:query])
      id = req[:path_params]["list_id"]

      case GatewayRpc.call(SukhiFedi.Lists, :timeline, [v.id, id, Map.to_list(opts)]) do
        {:ok, {:ok, notes}} when is_list(notes) ->
          body = Enum.map(notes, &MastodonStatus.render/1)
          headers = [{"content-type", "application/json"}]

          headers =
            case Pagination.link_header(
                   "/api/v1/timelines/list/#{id}",
                   notes,
                   & &1.id,
                   opts
                 ) do
              nil -> headers
              link -> [link | headers]
            end

          {:ok, %{status: 200, body: Jason.encode!(body), headers: headers}}

        {:ok, {:error, :not_found}} ->
          ok(404, %{error: "not_found"})

        e ->
          rpc_error(e)
      end
    end)
  end

  defp with_viewer(req, fun) do
    %{current_account: viewer} = req[:assigns]

    case viewer do
      nil -> ok(403, %{error: "this endpoint requires a user-bound token"})
      %{} = v -> fun.(v)
    end
  end

  defp decode_body(req) do
    case req[:body] do
      nil -> %{}
      "" -> %{}
      body when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, m} when is_map(m) -> m
          _ -> URI.decode_query(body)
        end

      body when is_map(body) ->
        body
    end
  end

  defp cs_errors(%{errors: errors}) do
    Map.new(errors, fn {k, {msg, _}} -> {k, msg} end)
  end

  defp cs_errors(_), do: %{}

  defp rpc_error({:error, :not_connected}), do: ok(503, %{error: "gateway_not_connected"})

  defp rpc_error({:error, {:badrpc, r}}),
    do: ok(503, %{error: "gateway_rpc_failed", detail: inspect(r)})

  defp rpc_error(_), do: ok(500, %{error: "internal_error"})

  defp ok(status, body) do
    {:ok,
     %{
       status: status,
       body: Jason.encode!(body),
       headers: [{"content-type", "application/json"}]
     }}
  end
end
