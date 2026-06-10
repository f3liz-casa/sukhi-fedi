# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.MediaProxyController do
  @moduledoc """
  リモートメディアを自ドメイン経由で配るプロキシ。閲覧者のブラウザを
  相手サーバへ直接行かせない(閲覧者の IP / UA を渡さない)ためのもので、
  URL そのものは受け取らず、DB の行を id で引く ─ だからオープン
  プロキシにはならないし、署名も要らない。

    * `/proxy/media/:id`  — リモート note の添付 (`media.remote_url`)
    * `/proxy/avatar/:id` — リモートアカウントの avatar
    * `/proxy/header/:id` — リモートアカウントの banner

  取得は `UrlGuard`(webfinger と同じ SSRF guard)を通し、redirect も
  一 hop ごとに再検査する。content-type は image / video / audio だけ、
  本文は `@max_bytes` まで ─ 外れたら 502。成功には長い cache-control を
  付けて CF edge に乗せる。帯域の本体はそちらが受けるので、BEAM まで
  来るのは cache miss だけ。

  本文は丸ごとメモリに置く(streaming しない)。`@max_bytes` がその
  上限で、edge cache が効く前提なら同時に並ぶ本数は少ない、という
  割り切り。足りなくなったら send_chunked への置き換えを考える。
  """

  import Plug.Conn

  alias SukhiFedi.Federation.UrlGuard
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Account
  alias SukhiFedi.Schema.Media

  @max_bytes 50 * 1024 * 1024
  @timeout_ms 20_000
  @max_redirects 3

  # 添付の remote_url は行ごと不変なので長め。avatar / banner は actor
  # 更新で URL が変わる(し、api 側が ?v= で cache bust する)ので一日。
  @media_cache "public, max-age=2592000"
  @profile_cache "public, max-age=86400"

  def media(conn, id_str) do
    with {id, ""} <- Integer.parse(id_str),
         %Media{remote_url: url} when is_binary(url) <- Repo.get(Media, id) do
      fetch(conn, url, @media_cache, @max_redirects)
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  def avatar(conn, id_str), do: profile_image(conn, id_str, :avatar_url)
  def header(conn, id_str), do: profile_image(conn, id_str, :banner_url)

  # リモートアカウント(domain あり)の画像だけ。ローカルの avatar は
  # /uploads/ 直なのでここへは来ない(来ても 404 でいい)。
  defp profile_image(conn, id_str, field) do
    with {id, ""} <- Integer.parse(id_str),
         %Account{domain: domain} = account when is_binary(domain) <- Repo.get(Account, id),
         url when is_binary(url) <- Map.get(account, field) do
      fetch(conn, url, @profile_cache, @max_redirects)
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  defp fetch(conn, _url, _cache_control, 0), do: send_resp(conn, 502, "")

  defp fetch(conn, url, cache_control, hops_left) do
    if UrlGuard.safe?(url) do
      case request(url) do
        {:ok, %Req.Response{status: 200, body: body} = resp} when is_binary(body) ->
          serve(conn, resp, cache_control)

        {:ok, %Req.Response{status: status} = resp} when status in [301, 302, 303, 307, 308] ->
          case Req.Response.get_header(resp, "location") do
            [location | _] ->
              next = URI.merge(url, location) |> URI.to_string()
              fetch(conn, next, cache_control, hops_left - 1)

            _ ->
              send_resp(conn, 502, "")
          end

        {:ok, %Req.Response{status: 404}} ->
          send_resp(conn, 404, "")

        _ ->
          send_resp(conn, 502, "")
      end
    else
      send_resp(conn, 502, "")
    end
  end

  defp request(url) do
    Req.get(url,
      redirect: false,
      retry: false,
      decode_body: false,
      receive_timeout: @timeout_ms,
      finch: SukhiFedi.Finch,
      into: &cap_body/2
    )
  end

  # @max_bytes を超えたら降ろすのをやめる。body が binary でなくなる
  # (= :too_large)ので、上の 200 節の is_binary match から外れて 502。
  defp cap_body({:data, data}, {req, resp}) do
    body = resp.body <> data

    if byte_size(body) > @max_bytes do
      {:halt, {req, %{resp | body: :too_large}}}
    else
      {:cont, {req, %{resp | body: body}}}
    end
  end

  defp serve(conn, %Req.Response{body: body} = resp, cache_control) do
    ct = resp |> Req.Response.get_header("content-type") |> List.first()

    if media_type?(ct) do
      conn
      |> put_resp_content_type(ct)
      |> put_resp_header("cache-control", cache_control)
      # serve_upload と同じ閉じ方: メディアはデータであって実行物では
      # ない。リモート由来ならなおさら。
      |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("content-disposition", "inline")
      |> send_resp(200, body)
    else
      send_resp(conn, 502, "")
    end
  end

  defp media_type?(ct) when is_binary(ct) do
    String.starts_with?(ct, "image/") or
      String.starts_with?(ct, "video/") or
      String.starts_with?(ct, "audio/")
  end

  defp media_type?(_), do: false
end
