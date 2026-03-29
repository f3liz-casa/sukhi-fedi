# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.StreamingController do
  import Plug.Conn
  alias SukhiFedi.Streaming.Registry
  alias SukhiFedi.Auth

  def stream(conn) do
    urn = conn.path_params["urn"]
    
    case urn do
      "home" -> stream_home(conn)
      "local" -> stream_local(conn)
      "public" -> stream_public(conn)
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp stream_home(conn) do
    with {:ok, account} <- authenticate(conn) do
      stream_sse(conn, :home, account.id)
    else
      {:error, :unauthorized} -> send_resp(conn, 401, "Unauthorized")
    end
  end

  defp stream_local(conn) do
    stream_sse(conn, :local, nil)
  end

  defp stream_public(conn) do
    stream_sse(conn, :public, nil)
  end

  defp stream_sse(conn, stream_type, account_id) do
    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> send_chunked(200)

    Registry.subscribe(stream_type, account_id)

    {:ok, conn} = chunk(conn, ":heartbeat\n\n")

    stream_loop(conn, stream_type, account_id)
  end

  defp stream_loop(conn, stream_type, account_id) do
    receive do
      {:stream_event, event} ->
        case format_sse(event) do
          {:ok, data} ->
            case chunk(conn, data) do
              {:ok, conn} -> stream_loop(conn, stream_type, account_id)
              {:error, _} -> cleanup(stream_type, account_id)
            end
          _ ->
            stream_loop(conn, stream_type, account_id)
        end
    after
      15_000 ->
        case chunk(conn, ":heartbeat\n\n") do
          {:ok, conn} -> stream_loop(conn, stream_type, account_id)
          {:error, _} -> cleanup(stream_type, account_id)
        end
    end
  end

  defp format_sse(%{event: event, payload: payload}) do
    case Jason.encode(payload) do
      {:ok, json} ->
        {:ok, "event: #{event}\ndata: #{json}\n\n"}
      error ->
        error
    end
  end

  defp cleanup(stream_type, account_id) do
    Registry.unsubscribe(stream_type, account_id)
    :ok
  end

  defp authenticate(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> Auth.verify_session(token)
      _ -> {:error, :unauthorized}
    end
  end
end
