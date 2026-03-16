# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.WebfingerController do
  import Plug.Conn

  alias SukhiFedi.AP.Client
  alias SukhiFedi.Cache.Ets

  @ttl_seconds 600

  def call(conn, _opts) do
    acct = conn.params["resource"]

    case Ets.get(:webfinger, acct) do
      {:ok, json} ->
        send_json(conn, json)

      :miss ->
        case Client.request("ap.webfinger", %{payload: %{acct: acct}}) do
          {:ok, json} ->
            Ets.put(:webfinger, acct, json, @ttl_seconds)
            send_json(conn, json)

          {:error, reason} ->
            send_resp(conn, 404, Jason.encode!(%{error: reason}))
        end
    end
  end

  defp send_json(conn, json) do
    conn
    |> put_resp_content_type("application/jrd+json")
    |> send_resp(200, Jason.encode!(json))
  end
end
