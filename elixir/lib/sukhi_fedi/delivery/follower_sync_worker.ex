# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Delivery.FollowerSyncWorker do
  @moduledoc """
  FEP-8fcf: Background Oban worker that fetches a remote actor's followers
  collection and reconciles local follow records.
  """

  use Oban.Worker, queue: :federation, max_attempts: 3

  alias SukhiFedi.Delivery.FollowersSync

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"actor_uri" => actor_uri, "collection_url" => collection_url}}) do
    case fetch_collection(collection_url) do
      {:ok, items} ->
        FollowersSync.reconcile(actor_uri, items)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_collection(url) do
    case Req.get(url,
           headers: [{"accept", "application/activity+json, application/ld+json"}],
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        items = Map.get(body, "items") || Map.get(body, "orderedItems") || []
        {:ok, items}

      {:ok, %{status: status}} ->
        {:error, "unexpected status #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end
end
