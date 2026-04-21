# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.InboxController do
  import Plug.Conn

  alias SukhiFedi.AP.Instructions
  alias SukhiFedi.Federation.FedifyClient

  # FEP-8fcf Collection-Synchronization format:
  #   collectionId="<uri>", url="<uri>", digest="<hex>"
  @sync_url_regex ~r/url="([^"]+)"/

  @follower_sync_worker "SukhiDelivery.Delivery.FollowerSyncWorker"
  @follower_sync_queue "federation"

  def user_inbox(conn, _opts) do
    handle_inbox(conn)
  end

  def shared_inbox(conn, _opts) do
    handle_inbox(conn)
  end

  defp handle_inbox(conn) do
    raw_json = conn.body_params
    sync_header = get_req_header(conn, "collection-synchronization") |> List.first()

    with {:ok, _} <- FedifyClient.verify(%{raw: raw_json}),
         {:ok, instruction} <- FedifyClient.inbox(%{raw: raw_json}) do
      Instructions.execute(instruction)
      maybe_enqueue_follower_sync(raw_json, sync_header)
      send_resp(conn, 202, "")
    else
      {:error, reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: reason}))
    end
  end

  defp maybe_enqueue_follower_sync(_raw_json, nil), do: :ok

  defp maybe_enqueue_follower_sync(raw_json, sync_header) do
    actor_uri = Map.get(raw_json, "actor")

    with true <- is_binary(actor_uri),
         [_, collection_url] <- Regex.run(@sync_url_regex, sync_header) do
      Oban.insert(
        Oban.Job.new(
          %{actor_uri: actor_uri, collection_url: collection_url},
          worker: @follower_sync_worker,
          queue: @follower_sync_queue
        )
      )
    end

    :ok
  end
end
