# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.BearerToken do
  @moduledoc """
  Pull an OAuth bearer token off a connection the Mastodon way.

  Browsers can't set an `Authorization` header on a WebSocket handshake
  or an `EventSource`, so Mastodon clients pass the token as the
  `access_token` query param; a non-browser client may send the header
  instead. Both streaming entry points (WebSocket and SSE) read it the
  same way, so the rule lives here.
  """

  @doc "The bearer token from `?access_token=` or an `Authorization` header, or `nil`."
  @spec extract(Plug.Conn.t()) :: String.t() | nil
  def extract(conn) do
    case conn.query_params["access_token"] do
      token when is_binary(token) and token != "" -> token
      _ -> header_token(conn)
    end
  end

  defp header_token(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> token
      _ -> nil
    end
  end
end
