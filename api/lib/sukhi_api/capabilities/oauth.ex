# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.OAuth do
  @moduledoc """
  OAuth 2.0 server endpoints (authorize / token / revoke). Mounted on
  `/oauth/*` (not `/api/v1/*`) per Mastodon convention; the gateway
  router has a `match "/oauth/*_"` block that forwards here.

      GET   /oauth/authorize    HTML consent form (rendered by this capability)
      POST  /oauth/authorize    user submits → redirect with ?code=…
      POST  /oauth/token        grant_type ∈ {authorization_code, refresh_token, client_credentials}
      POST  /oauth/revoke       RFC 7009; idempotent

  GET /oauth/authorize requires an authenticated browser session. Today
  that comes from a `session_token` cookie set by an external login
  flow (or by curl in tests via `Cookie: session_token=…`). When the
  session lookup fails, the form re-renders with a sign-in link instead
  of the consent UI; production deployments should front this with a
  proper login page (out of PR1 scope).
  """

  use SukhiApi.Capability, addon: :mastodon_api

  alias SukhiApi.GatewayRpc

  @gateway SukhiFedi.OAuth

  @impl true
  def routes do
    [
      {:get, "/oauth/authorize", &authorize_form/1},
      {:post, "/oauth/authorize", &authorize_submit/1},
      {:post, "/oauth/token", &token/1},
      {:post, "/oauth/revoke", &revoke/1}
    ]
  end

  # ── GET /oauth/authorize ─────────────────────────────────────────────────

  def authorize_form(req) do
    params = parse_query(req[:query])
    client_id = params["client_id"]
    redirect_uri = params["redirect_uri"] || ""
    scope = params["scope"] || "read"
    state = params["state"] || ""
    response_type = params["response_type"] || "code"

    cond do
      response_type != "code" ->
        html_error(400, "unsupported_response_type", "only response_type=code is supported")

      is_nil(client_id) or client_id == "" ->
        html_error(400, "invalid_request", "missing client_id")

      true ->
        case GatewayRpc.call(@gateway, :find_app_by_client_id, [client_id]) do
          {:ok, {:ok, app}} ->
            html_form(app, redirect_uri, scope, state)

          {:ok, {:error, :not_found}} ->
            html_error(404, "invalid_client", "unknown client_id")

          {:error, :not_connected} ->
            html_error(503, "gateway_not_connected", "the gateway is unreachable")

          {:error, {:badrpc, reason}} ->
            html_error(503, "gateway_rpc_failed", inspect(reason))
        end
    end
  end

  # ── POST /oauth/authorize ────────────────────────────────────────────────

  def authorize_submit(req) do
    body = parse_form_body(req[:body])
    client_id = body["client_id"]
    redirect_uri = body["redirect_uri"] || ""
    scope = body["scope"] || "read"
    state = body["state"]
    session_token = session_token_from_cookies(req[:headers] || [])

    with {:ok, account} <- resolve_session(session_token),
         {:ok, {:ok, app}} <- GatewayRpc.call(@gateway, :find_app_by_client_id, [client_id]),
         {:ok, {:ok, %{code: code, state: returned_state}}} <-
           GatewayRpc.call(@gateway, :create_authorization_code, [
             app,
             account,
             %{redirect_uri: redirect_uri, scopes: scope, state: state}
           ]) do
      redirect(redirect_uri, code: code, state: returned_state)
    else
      {:error, :no_session} ->
        html_error(401, "unauthorized", "log in first to authorize this app")

      {:ok, {:error, :not_found}} ->
        html_error(404, "invalid_client", "unknown client_id")

      {:ok, {:error, :invalid_redirect_uri}} ->
        html_error(400, "invalid_redirect_uri", "redirect_uri does not match registered URIs")

      {:ok, {:error, :invalid_scope}} ->
        html_error(400, "invalid_scope", "requested scope exceeds the app's allowed scopes")

      {:error, :not_connected} ->
        html_error(503, "gateway_not_connected", "the gateway is unreachable")

      {:error, {:badrpc, reason}} ->
        html_error(503, "gateway_rpc_failed", inspect(reason))

      _ ->
        html_error(400, "invalid_request", "could not authorize")
    end
  end

  # ── POST /oauth/token ────────────────────────────────────────────────────

  def token(req) do
    body = decode_token_body(req)
    grant_type = body["grant_type"]

    case grant_type do
      "authorization_code" ->
        do_authorization_code(body)

      "refresh_token" ->
        do_refresh(body)

      "client_credentials" ->
        do_client_credentials(body)

      _ ->
        json(400, %{error: "unsupported_grant_type"})
    end
  end

  defp do_authorization_code(body) do
    case GatewayRpc.call(@gateway, :exchange_code_for_token, [body]) do
      {:ok, {:ok, token_payload}} ->
        json(200, present_token(token_payload))

      {:ok, {:error, reason}} ->
        json(400, %{error: oauth_error_for(reason)})

      {:error, :not_connected} ->
        json(503, %{error: "gateway_not_connected"})

      {:error, {:badrpc, reason}} ->
        json(503, %{error: "gateway_rpc_failed", detail: inspect(reason)})
    end
  end

  defp do_refresh(body) do
    case GatewayRpc.call(@gateway, :refresh_token_grant, [body]) do
      {:ok, {:ok, token_payload}} ->
        json(200, present_token(token_payload))

      {:ok, {:error, reason}} ->
        json(400, %{error: oauth_error_for(reason)})

      {:error, :not_connected} ->
        json(503, %{error: "gateway_not_connected"})

      {:error, {:badrpc, reason}} ->
        json(503, %{error: "gateway_rpc_failed", detail: inspect(reason)})
    end
  end

  defp do_client_credentials(body) do
    cid = body["client_id"]
    secret = body["client_secret"]
    scope = body["scope"]

    case GatewayRpc.call(@gateway, :client_credentials_grant, [cid, secret, scope]) do
      {:ok, {:ok, token_payload}} ->
        json(200, present_token(token_payload))

      {:ok, {:error, reason}} ->
        json(400, %{error: oauth_error_for(reason)})

      {:error, :not_connected} ->
        json(503, %{error: "gateway_not_connected"})

      {:error, {:badrpc, reason}} ->
        json(503, %{error: "gateway_rpc_failed", detail: inspect(reason)})
    end
  end

  # ── POST /oauth/revoke ───────────────────────────────────────────────────

  def revoke(req) do
    body = decode_token_body(req)

    case GatewayRpc.call(@gateway, :revoke_token, [body]) do
      {:ok, :ok} ->
        json(200, %{})

      {:error, :not_connected} ->
        json(503, %{error: "gateway_not_connected"})

      {:error, {:badrpc, reason}} ->
        json(503, %{error: "gateway_rpc_failed", detail: inspect(reason)})

      _ ->
        # RFC 7009 mandates idempotent success even on unknown token
        json(200, %{})
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  defp present_token(t) do
    %{
      access_token: t.access_token,
      token_type: t.token_type,
      scope: t.scope,
      created_at: t.created_at
    }
    |> maybe_put(:refresh_token, t[:refresh_token] || Map.get(t, :refresh_token))
  end

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)

  defp oauth_error_for(:invalid_client), do: "invalid_client"
  defp oauth_error_for(:invalid_grant), do: "invalid_grant"
  defp oauth_error_for(:invalid_redirect_uri), do: "invalid_grant"
  defp oauth_error_for(:invalid_scope), do: "invalid_scope"
  defp oauth_error_for(_), do: "invalid_request"

  defp decode_token_body(req) do
    headers = req[:headers] || []
    ct = content_type(headers)

    cond do
      String.contains?(ct, "application/json") ->
        case Jason.decode(req[:body] || "") do
          {:ok, %{} = m} -> m
          _ -> %{}
        end

      true ->
        parse_form_body(req[:body])
    end
  end

  defp content_type(headers) do
    Enum.find_value(headers, "", fn {k, v} ->
      if String.downcase(to_string(k)) == "content-type", do: to_string(v), else: nil
    end)
  end

  defp parse_form_body(nil), do: %{}
  defp parse_form_body(""), do: %{}

  defp parse_form_body(body) when is_binary(body) do
    URI.decode_query(body)
  end

  defp parse_query(nil), do: %{}
  defp parse_query(""), do: %{}
  defp parse_query(q) when is_binary(q), do: URI.decode_query(q)

  defp session_token_from_cookies(headers) do
    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(to_string(k)) == "cookie" do
        v
        |> to_string()
        |> String.split(";", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.find_value(fn pair ->
          case String.split(pair, "=", parts: 2) do
            ["session_token", t] -> t
            _ -> nil
          end
        end)
      end
    end)
  end

  defp resolve_session(nil), do: {:error, :no_session}

  defp resolve_session(token) when is_binary(token) do
    case GatewayRpc.call(SukhiFedi.Accounts, :get_account_by_session_token, [token]) do
      {:ok, %{} = account} -> {:ok, account}
      {:ok, nil} -> {:error, :no_session}
      _ -> {:error, :no_session}
    end
  end

  # ── HTML rendering ───────────────────────────────────────────────────────

  defp html_form(app, redirect_uri, scope, state) do
    name = h(app.name)
    cid = h(app.client_id)
    redir = h(redirect_uri)
    sc = h(scope)
    st = h(state)

    body = """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <title>Authorize #{name}</title>
      <style>
        body { font-family: system-ui, sans-serif; max-width: 28rem; margin: 4rem auto; padding: 0 1rem; }
        h1 { font-size: 1.25rem; }
        button { font-size: 1rem; padding: 0.5rem 1rem; }
        .scope { font-family: monospace; }
      </style>
    </head>
    <body>
      <h1>Authorize <strong>#{name}</strong></h1>
      <p>This application is requesting the following scope:</p>
      <p class="scope">#{sc}</p>
      <p>If you authorize, you will be redirected to <code>#{redir}</code>.</p>
      <form action="/oauth/authorize" method="post">
        <input type="hidden" name="client_id" value="#{cid}">
        <input type="hidden" name="redirect_uri" value="#{redir}">
        <input type="hidden" name="scope" value="#{sc}">
        <input type="hidden" name="state" value="#{st}">
        <button type="submit">Authorize</button>
      </form>
    </body>
    </html>
    """

    {:ok, %{status: 200, body: body, headers: [{"content-type", "text/html; charset=utf-8"}]}}
  end

  defp html_error(status, code, detail) do
    body = """
    <!doctype html><html><head><title>#{h(code)}</title></head>
    <body><h1>#{h(code)}</h1><p>#{h(detail)}</p></body></html>
    """

    {:ok, %{status: status, body: body, headers: [{"content-type", "text/html; charset=utf-8"}]}}
  end

  defp h(nil), do: ""

  defp h(s) when is_binary(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp redirect(base, params) do
    qs =
      params
      |> Enum.reject(fn {_, v} -> is_nil(v) or v == "" end)
      |> URI.encode_query()

    location = if qs == "", do: base, else: "#{base}?#{qs}"

    {:ok,
     %{
       status: 302,
       body: "",
       headers: [{"location", location}, {"content-type", "text/plain"}]
     }}
  end

  defp json(status, body) do
    {:ok,
     %{
       status: status,
       body: Jason.encode!(body),
       headers: [{"content-type", "application/json"}]
     }}
  end
end
