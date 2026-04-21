# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Federation.ActorFetcher do
  @moduledoc """
  Fetches remote ActivityPub Actor JSON documents over HTTPS and caches
  them in ETS (`:actor_remote` table).

  Replaces the old 3-hop pattern (Elixir → Bun → Elixir → cache → reply)
  with a single direct GET from Elixir + node-local cache.
  """

  require Logger
  alias SukhiFedi.Cache.Ets

  @ttl_seconds 3_600
  @timeout_ms 10_000

  @spec fetch(String.t()) :: {:ok, map()} | {:error, term()}
  def fetch(actor_uri) when is_binary(actor_uri) do
    case Ets.get(:actor_remote, actor_uri) do
      {:ok, actor} -> {:ok, actor}
      :miss -> do_fetch(actor_uri)
    end
  end

  defp do_fetch(actor_uri) do
    headers = [
      {"accept", "application/activity+json, application/ld+json"},
      {"user-agent", "sukhi-fedi/0.1.0"}
    ]

    case Req.get(actor_uri, headers: headers, receive_timeout: @timeout_ms) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        Ets.put(:actor_remote, actor_uri, body, @ttl_seconds)
        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, actor} ->
            Ets.put(:actor_remote, actor_uri, actor, @ttl_seconds)
            {:ok, actor}

          {:error, reason} ->
            {:error, {:invalid_json, reason}}
        end

      {:ok, %{status: status}} ->
        Logger.warning("ActorFetcher: #{actor_uri} returned HTTP #{status}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        Logger.warning("ActorFetcher: #{actor_uri} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
