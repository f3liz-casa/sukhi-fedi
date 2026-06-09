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
  proper login page.
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
    session_token = session_token_from_cookies(req[:headers] || [])

    cond do
      response_type != "code" ->
        html_error(400, "unsupported_response_type", "only response_type=code is supported")

      is_nil(client_id) or client_id == "" ->
        html_error(400, "invalid_request", "missing client_id")

      true ->
        case resolve_session(session_token) do
          {:error, :no_session} ->
            # ログインしていない人に consent 画面を見せない。`/login`
            # に飛ばし、ログインが済んだら同じ /oauth/authorize?... に
            # 戻ってこられるよう `next` に元 URL を載せる。
            next = "/oauth/authorize?" <> (req[:query] || "")
            redirect_to_login(next)

          {:ok, account} ->
            authorize_with_session(account, client_id, redirect_uri, scope, state)
        end
    end
  end

  # 自分のサーバの SPA に「自分が自分を許可する?」を聞くのは形式で
  # しかないので、redirect_uri が自ホストなら consent を出さずに即
  # code を発行する。外部の Mastodon クライアント等(別ホスト)が来た
  # ときは従来どおり consent form。
  defp authorize_with_session(account, client_id, redirect_uri, scope, state) do
    case GatewayRpc.call(@gateway, :find_app_by_client_id, [client_id]) do
      {:ok, {:ok, app}} ->
        if first_party?(redirect_uri) do
          mint_and_redirect(app, account, redirect_uri, scope, state)
        else
          html_form(app, redirect_uri, scope, state)
        end

      {:ok, {:error, :not_found}} ->
        html_error(404, "invalid_client", "unknown client_id")

      {:error, :not_connected} ->
        html_error(503, "gateway_not_connected", "the gateway is unreachable")

      {:error, {:badrpc, reason}} ->
        html_error(503, "gateway_rpc_failed", inspect(reason))
    end
  end

  defp mint_and_redirect(app, account, redirect_uri, scope, state) do
    case GatewayRpc.call(@gateway, :create_authorization_code, [
           app,
           account,
           %{redirect_uri: redirect_uri, scopes: scope, state: state}
         ]) do
      {:ok, {:ok, %{code: code, state: returned_state}}} ->
        redirect(redirect_uri, code: code, state: returned_state)

      {:ok, {:error, :invalid_redirect_uri}} ->
        html_error(400, "invalid_redirect_uri", "redirect_uri does not match registered URIs")

      {:ok, {:error, :invalid_scope}} ->
        html_error(400, "invalid_scope", "requested scope exceeds the app's allowed scopes")

      {:error, :not_connected} ->
        html_error(503, "gateway_not_connected", "the gateway is unreachable")

      {:error, {:badrpc, reason}} ->
        html_error(503, "gateway_rpc_failed", inspect(reason))
    end
  end

  defp first_party?(redirect_uri) when is_binary(redirect_uri) do
    case URI.parse(redirect_uri) do
      %URI{host: host} when is_binary(host) ->
        host == SukhiApi.Config.domain!() |> strip_port()

      _ ->
        false
    end
  end

  defp first_party?(_), do: false

  defp strip_port(domain), do: domain |> String.split(":", parts: 2) |> hd()

  defp redirect_to_login(next) do
    location = "/login?next=" <> URI.encode_www_form(next)

    {:ok,
     %{
       status: 302,
       body: "",
       headers: [{"location", location}]
     }}
  end

  # ── POST /oauth/authorize ────────────────────────────────────────────────

  def authorize_submit(req) do
    # POST /oauth/authorize は同意フォーム(ブラウザの form submit)から
    # 来るので元の content-type は application/x-www-form-urlencoded だが、
    # `SukhiFedi.Web.PluginPlug` が body_params を JSON に再エンコード
    # してから渡してくる(`plugin_plug.ex` の `body =` 参照)。なので
    # ここは JSON で読む。直接呼ばれた古いテスト等のために
    # form 形式へのフォールバックも残す。
    body = decode_request_body(req)
    client_id = body["client_id"]
    redirect_uri = body["redirect_uri"] || ""
    scope = body["scope"] || "read"
    state = body["state"]
    session_token = session_token_from_cookies(req[:headers] || [])

    cond do
      is_nil(client_id) or client_id == "" ->
        html_error(400, "invalid_request", "missing client_id")

      true ->
        do_authorize_submit(client_id, redirect_uri, scope, state, session_token)
    end
  end

  defp do_authorize_submit(client_id, redirect_uri, scope, state, session_token) do
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
    |> maybe_put(:expires_in, t[:expires_in] || Map.get(t, :expires_in))
  end

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)

  defp oauth_error_for(:invalid_client), do: "invalid_client"
  defp oauth_error_for(:invalid_grant), do: "invalid_grant"
  defp oauth_error_for(:invalid_redirect_uri), do: "invalid_grant"
  defp oauth_error_for(:invalid_scope), do: "invalid_scope"
  defp oauth_error_for(_), do: "invalid_request"

  defp decode_token_body(req), do: decode_request_body(req)

  # PluginPlug が body_params を JSON 再エンコードして渡してくるので、
  # まず JSON で読む。空 body や、テストなどで直接 form 文字列が来た
  # 場合は URI.decode_query へフォールバック。
  defp decode_request_body(req) do
    raw = req[:body] || ""

    case JSON.decode(raw) do
      {:ok, %{} = m} -> m
      _ -> parse_form_body(raw)
    end
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

    scope_list = render_scope_list(scope)

    body = """
    <!doctype html>
    <html lang="ja">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>許可する — sukhi-fedi</title>
      <link rel="stylesheet" href="/static/styles/app.css" />
    </head>
    <body>
      <main class="wrap stack">
        <section class="hero">
          <h1>#{name} に、許可しますか?</h1>
          <p class="tagline">この道具に、こんなことが、できるようになります。</p>
        </section>
        #{scope_list}
        <p class="prose-small">
          「いいよ」を押すと、<code>#{redir}</code> に戻ります。
        </p>
        <form action="/oauth/authorize" method="post" class="form stack">
          <input type="hidden" name="client_id" value="#{cid}">
          <input type="hidden" name="redirect_uri" value="#{redir}">
          <input type="hidden" name="scope" value="#{sc}">
          <input type="hidden" name="state" value="#{st}">
          <button type="submit">いいよ</button>
        </form>
        <p class="prose-small"><a href="/">やめておく</a></p>
      </main>
    </body>
    </html>
    """

    {:ok, %{status: 200, body: body, headers: [{"content-type", "text/html; charset=utf-8"}]}}
  end

  # scope は空白区切り (Mastodon 互換)。"read write follow" や
  # "read:statuses write:statuses" のような形で来る。1 つずつ短い
  # 日本語に直して、見たことのない sub-scope はそのまま並べる。
  defp render_scope_list(scope) do
    items =
      scope
      |> to_string()
      |> String.split([" ", "+"], trim: true)
      |> Enum.uniq()
      |> Enum.map(&scope_explain/1)
      |> Enum.map(fn {label, detail} ->
        "<li><strong>#{h(label)}</strong> — #{h(detail)}</li>"
      end)
      |> Enum.join("\n          ")

    case items do
      "" -> ""
      _ -> ~s|<ul class="scope-list">\n          #{items}\n        </ul>|
    end
  end

  # 既知の scope はやさしい日本語で。未知のものはそのまま見せて、
  # ぼかさずに「これがついています」と置く。
  defp scope_explain("read"), do: {"読む", "あなたのところで起きていることを、読みます。"}
  defp scope_explain("write"), do: {"書く", "あなたに代わって、投稿したり、プロフィールを変えたりします。"}
  defp scope_explain("follow"),
    do: {"フォロー", "あなたに代わって、誰かをフォロー/アンフォローします。"}

  defp scope_explain("push"), do: {"通知", "新しい通知を、この道具に届けます。"}

  defp scope_explain("read:accounts"),
    do: {"アカウントを読む", "あなたや他の人のプロフィールを、読みます。"}

  defp scope_explain("read:statuses"),
    do: {"投稿を読む", "タイムラインや個別の投稿を、読みます。"}

  defp scope_explain("read:notifications"),
    do: {"通知を読む", "届いた通知を、読みます。"}

  defp scope_explain("read:follows"),
    do: {"フォローを読む", "あなたがフォローしている人/されている人を、読みます。"}

  defp scope_explain("write:statuses"),
    do: {"投稿を書く", "あなたに代わって、投稿したり、消したりします。"}

  defp scope_explain("write:media"),
    do: {"画像を上げる", "投稿に添える画像などを、サーバへ上げます。"}

  defp scope_explain("write:accounts"),
    do: {"プロフィールを変える", "あなたの表示名・自己紹介・アイコンを、書き換えます。"}

  defp scope_explain("write:follows"),
    do: {"フォローを変える", "あなたに代わって、フォロー/アンフォローします。"}

  defp scope_explain("write:notifications"),
    do: {"通知を整える", "通知を消したり、まとめて既読にしたりします。"}

  defp scope_explain(other), do: {other, "この権限の説明は、まだ用意していません。"}

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
       body: JSON.encode!(body),
       headers: [{"content-type", "application/json"}]
     }}
  end
end
