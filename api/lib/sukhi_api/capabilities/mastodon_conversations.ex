# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MastodonConversations do
  @moduledoc """
  Mastodon conversations index.

      GET   /api/v1/conversations    read:statuses

  Returns one row per conversation the viewer participates in, with
  the most-recent DM Note and the other participants' accounts.
  Unread tracking is a deferred concern (always `false` for now).
  """

  use SukhiApi.Capability, addon: :mastodon_api

  alias SukhiApi.{GatewayRpc, Pagination}
  alias SukhiApi.Views.{MastodonAccount, MastodonStatus}

  @impl true
  def routes do
    [
      {:get, "/api/v1/conversations", &index/1, scope: "read:statuses"}
    ]
  end

  def index(req) do
    %{current_account: viewer} = req[:assigns]

    case viewer do
      nil ->
        ok(403, %{error: "this endpoint requires a user-bound token"})

      %{} = v ->
        opts = Pagination.parse_opts(req[:query])

        case GatewayRpc.call(SukhiFedi.Conversations, :list, [v.id, Map.to_list(opts)]) do
          {:ok, list} when is_list(list) ->
            body = Enum.map(list, &render/1)
            ok(200, body)

          e ->
            rpc_error(e)
        end
    end
  end

  defp render(%{id: cid, unread: u, accounts: accounts, last_status: status}) do
    %{
      id: cid,
      unread: !!u,
      accounts: Enum.map(accounts, &MastodonAccount.render(&1, %{})),
      last_status: MastodonStatus.render(status)
    }
  end

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
