# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.InboxController do
  import Plug.Conn

  alias SukhiFedi.AP.Client
  alias SukhiFedi.AP.Instructions

  def user_inbox(conn, _opts) do
    handle_inbox(conn)
  end

  def shared_inbox(conn, _opts) do
    handle_inbox(conn)
  end

  defp handle_inbox(conn) do
    raw_json = conn.body_params

    with {:ok, _} <- Client.request("ap.verify", %{payload: raw_json}),
         {:ok, instruction} <- Client.request("ap.inbox", %{payload: raw_json}) do
      Instructions.execute(instruction)
      send_resp(conn, 202, "")
    else
      {:error, reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: reason}))
    end
  end
end
