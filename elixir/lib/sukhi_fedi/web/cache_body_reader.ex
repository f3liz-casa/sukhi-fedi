# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.CacheBodyReader do
  @moduledoc """
  Body reader for `Plug.Parsers` that stashes the unparsed bytes in
  `conn.assigns.raw_body` so downstream handlers (HTTP-Signature
  verification) can see exactly what the remote server signed.
  """

  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = update_in(conn.assigns[:raw_body], fn prev -> (prev || "") <> body end)
    {:ok, body, conn}
  end
end
