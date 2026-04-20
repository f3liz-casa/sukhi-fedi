# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.RateLimitPlug do
  @moduledoc """
  Per-peer rate limiter backed by Hammer (ETS buckets, node-local).

  Intended for externally-reachable endpoints — the inbox, WebFinger,
  and Mastodon-compat API. Node-local is fine because abusive remote
  servers will hit every node roughly equally if we're scaled
  horizontally.

  Options:
    * `:limit`     — allowed hits per window (default 100)
    * `:scale_ms`  — window length (default 60_000 ms)
    * `:bucket`    — label prefix, lets different routes share limits
                     or isolate them (default "rl")

  Example:

      plug SukhiFedi.Web.RateLimitPlug, bucket: "inbox", limit: 300, scale_ms: 60_000
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts) do
    %{
      limit: Keyword.get(opts, :limit, 100),
      scale_ms: Keyword.get(opts, :scale_ms, 60_000),
      bucket: Keyword.get(opts, :bucket, "rl")
    }
  end

  @impl true
  def call(conn, %{limit: limit, scale_ms: scale_ms, bucket: bucket}) do
    key = "#{bucket}:#{peer_id(conn)}"

    case Hammer.check_rate(key, scale_ms, limit) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(div(scale_ms, 1_000)))
        |> put_resp_content_type("application/json")
        |> send_resp(429, Jason.encode!(%{error: "rate_limited"}))
        |> halt()
    end
  end

  defp peer_id(%Plug.Conn{} = conn) do
    # Trust X-Forwarded-For only if set by our own reverse proxy — this
    # naive version just uses the socket peer. Swap in a PlugForwardedFor
    # here when the deployment terminates TLS elsewhere.
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end
end
