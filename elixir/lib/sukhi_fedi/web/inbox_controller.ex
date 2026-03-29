# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.InboxController do
  import Plug.Conn

  alias SukhiFedi.AP.Client
  alias SukhiFedi.AP.Instructions
  alias SukhiFedi.Delivery.{FollowersSync, FollowerSyncWorker}

  def user_inbox(conn, _opts) do
    handle_inbox(conn)
  end

  def shared_inbox(conn, _opts) do
    handle_inbox(conn)
  end

  defp handle_inbox(conn) do
    raw_json = conn.body_params

    # FEP-8fcf: parse Collection-Synchronization header for async reconciliation
    sync_header = get_req_header(conn, "collection-synchronization") |> List.first()

    with {:ok, _} <- Client.request("ap.verify", %{payload: raw_json}),
         {:ok, instruction} <- Client.request("ap.inbox", %{payload: raw_json}) do
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
         {:ok, %{url: collection_url}} <- FollowersSync.parse_header(sync_header) do
      %{actor_uri: actor_uri, collection_url: collection_url}
      |> FollowerSyncWorker.new()
      |> Oban.insert()
    end

    :ok
  end
end
