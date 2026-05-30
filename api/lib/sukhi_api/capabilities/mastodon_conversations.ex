# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MastodonConversations do
  @moduledoc """
  Mastodon conversations.

      GET   /api/v1/conversations           read:statuses
      POST  /api/v1/conversations/:id/read  write:conversations

  `index` returns one row per conversation the viewer participates in,
  with the most-recent DM Note, the other participants' accounts, and the
  viewer's `unread` flag. `read` clears that flag. The conversation `id`
  is the viewer's participant row id (a plain number), so the `:id` path
  segment maps straight back to the row.
  """

  use SukhiApi.Capability, addon: :mastodon_api

  alias SukhiApi.{GatewayRpc, Pagination}
  alias SukhiApi.Views.{MastodonAccount, MastodonStatus}

  @impl true
  def routes do
    [
      {:get, "/api/v1/conversations", &index/1, scope: "read:statuses"},
      {:post, "/api/v1/conversations/:id/read", &read/1, scope: "write:conversations"}
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

  @doc """
  Fan a just-created DM out to each local participant's `direct` stream.
  The gateway returns the per-participant conversation data; we render it
  here (views live on this node) and hand the rendered payloads back to
  the gateway to broadcast. Best-effort — never lets streaming fail a
  post — so callers should run it off the response path.
  """
  def stream_new_dm(conversation_ap_id) when is_binary(conversation_ap_id) do
    with {:ok, targets} when is_list(targets) <-
           GatewayRpc.call(SukhiFedi.Conversations, :fanout_entries, [conversation_ap_id]) do
      payload =
        Enum.map(targets, fn %{account_id: account_id, entry: entry} ->
          %{account_id: account_id, conversation: render(entry)}
        end)

      GatewayRpc.call(SukhiFedi.Streaming, :publish_direct, [payload])
    end

    :ok
  rescue
    _ -> :ok
  end

  def stream_new_dm(_), do: :ok

  def read(req) do
    %{current_account: viewer} = req[:assigns]
    id = req[:path_params]["id"]

    case viewer do
      nil ->
        ok(403, %{error: "this endpoint requires a user-bound token"})

      %{} = v ->
        case GatewayRpc.call(SukhiFedi.Conversations, :mark_read, [v.id, id]) do
          {:ok, {:ok, entry}} -> ok(200, render(entry))
          {:ok, {:error, :not_found}} -> ok(404, %{error: "not_found"})
          e -> rpc_error(e)
        end
    end
  end

  defp render(%{id: id, unread: u, accounts: accounts, last_status: status}) do
    %{
      id: to_string(id),
      unread: !!u,
      accounts: Enum.map(accounts, &MastodonAccount.render(&1, %{})),
      last_status: status && MastodonStatus.render(status)
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
