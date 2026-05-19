# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MastodonPolls do
  @moduledoc """
  Polls surface.

      GET   /api/v1/polls/:id          read:statuses
      POST  /api/v1/polls/:id/votes    write:statuses

  Vote body accepts either `choices[]=<index>` (Mastodon's wire form)
  or `choices=<index>`. Indices are 0-based positions in the option
  list; option PKs work too for clients that resolved them already.
  """

  use SukhiApi.Capability, addon: :mastodon_api

  alias SukhiApi.GatewayRpc
  alias SukhiApi.Views.MastodonPoll

  @impl true
  def routes do
    [
      {:get, "/api/v1/polls/:id", &show/1, scope: "read:statuses"},
      {:post, "/api/v1/polls/:id/votes", &vote/1, scope: "write:statuses"}
    ]
  end

  def show(req) do
    viewer_id =
      case req[:assigns][:current_account] do
        %{id: id} -> id
        _ -> nil
      end

    id = req[:path_params]["id"]

    case GatewayRpc.call(SukhiFedi.Polls, :get_with_results, [id, viewer_id]) do
      {:ok, {:ok, ctx}} -> ok(200, MastodonPoll.render(ctx))
      {:ok, {:error, :not_found}} -> ok(404, %{error: "not_found"})
      e -> rpc_error(e)
    end
  end

  def vote(req) do
    %{current_account: viewer} = req[:assigns]

    case viewer do
      nil ->
        ok(403, %{error: "this endpoint requires a user-bound token"})

      %{} = v ->
        id = req[:path_params]["id"]
        body = decode_body(req)
        choices = body["choices[]"] || body["choices"] || []
        choices = List.wrap(choices)

        case GatewayRpc.call(SukhiFedi.Polls, :vote, [v.id, id, choices]) do
          {:ok, :ok} ->
            case GatewayRpc.call(SukhiFedi.Polls, :get_with_results, [id, v.id]) do
              {:ok, {:ok, ctx}} -> ok(200, MastodonPoll.render(ctx))
              _ -> ok(200, %{})
            end

          {:ok, {:error, :not_found}} ->
            ok(404, %{error: "not_found"})

          {:ok, {:error, :expired}} ->
            ok(422, %{error: "poll_expired"})

          {:ok, {:error, :too_many_choices}} ->
            ok(422, %{error: "too_many_choices"})

          e ->
            rpc_error(e)
        end
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
