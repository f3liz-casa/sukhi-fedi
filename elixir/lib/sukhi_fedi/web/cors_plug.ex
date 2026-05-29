# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.CorsPlug do
  @moduledoc """
  Permissive CORS so browser-based Mastodon clients (Elk, Phanpy, …) can
  call the API cross-origin.

  Those clients run on their own origin (e.g. `main.elk.zone`) and hit us
  with XHR/fetch, so the browser fires a preflight `OPTIONS` first and
  blocks the real request unless we answer it with `Access-Control-*`
  headers. Without this every third-party web client fails right after
  the OAuth token exchange — the preflight on `verify_credentials` /
  `timelines/home` 404s and the login looks broken.

  They authenticate with a Bearer token, not cookies, so
  `Access-Control-Allow-Origin: *` is both correct and safe — it's what
  Mastodon itself sends, and `*` makes browsers refuse credentialed
  (cookie) cross-origin requests, so the gateway's own cookie session
  can't be ridden from another origin.

  Preflight is answered here (204) before routing so it never falls
  through to a 404; for every other request the headers are attached via
  `register_before_send/2`, so they land regardless of which handler
  (incl. the plugin-node forwarder) sends the response.
  """
  import Plug.Conn

  @allow_methods "GET, POST, PUT, PATCH, DELETE, OPTIONS"
  @default_allow_headers "authorization, content-type, idempotency-key"
  @expose_headers "link, x-ratelimit-limit, x-ratelimit-remaining, x-ratelimit-reset"

  def init(opts), do: opts

  def call(%Plug.Conn{method: "OPTIONS"} = conn, _opts) do
    conn
    |> cors_headers()
    |> put_resp_header("access-control-allow-methods", @allow_methods)
    |> put_resp_header("access-control-allow-headers", requested_headers(conn))
    |> put_resp_header("access-control-max-age", "86400")
    |> send_resp(204, "")
    |> halt()
  end

  def call(conn, _opts) do
    register_before_send(conn, &cors_headers/1)
  end

  defp cors_headers(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-expose-headers", @expose_headers)
  end

  # Echo the browser's requested headers when it sends them (some clients
  # add custom ones); fall back to the common set otherwise.
  defp requested_headers(conn) do
    case get_req_header(conn, "access-control-request-headers") do
      [h | _] when is_binary(h) and h != "" -> h
      _ -> @default_allow_headers
    end
  end
end
