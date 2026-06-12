# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Auth.MailIpGate do
  @moduledoc """
  Per-IP ceiling on the unauthenticated mail-sending endpoints
  (`/signup/email/request`, `/login/email/request`).

  This is the valve against direct curl/bot hammering. An Anubis
  CHALLENGE on these XHRs was tried first (2026-06-13) and reverted:
  this Anubis re-challenges fetch POSTs even right after the browser
  solved /check, which deadlocked real users — see
  `config/anubis/botPolicies.yaml` for the post-mortem. So the
  browser-vs-bot distinction stays at /check (the only place the UI
  sends mail from), and this gate plus the per-address limits in
  `EmailAuth` bound what a cookie-less script can pump out.

  12 sends/hour/IP is roomy for a human (several resends across both
  doors) and slow for a bot. Tests raise the ceiling via config.
  """

  @default_limit 12
  @scale_ms 60 * 60 * 1000

  @spec ok?(Plug.Conn.t()) :: boolean()
  def ok?(conn) do
    limit = Application.get_env(:sukhi_fedi, :mail_ip_limit, @default_limit)
    key = "mailgate:" <> SukhiFedi.Web.RateLimitPlug.peer_id(conn)

    case Hammer.check_rate(key, @scale_ms, limit) do
      {:allow, _} -> true
      {:deny, _} -> false
    end
  end
end
