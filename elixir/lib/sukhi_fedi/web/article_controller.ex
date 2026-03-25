# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.ArticleController do
  import Plug.Conn
  alias SukhiFedi.{Articles, Auth}

  def create(conn) do
    with {:ok, account} <- authenticate(conn),
         {:ok, body, conn} <- read_body(conn),
         {:ok, params} <- Jason.decode(body),
         {:ok, article} <- create_article(account, params) do
      send_json(conn, 201, serialize_article(article))
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
      _ -> send_json(conn, 400, %{error: "invalid_request", message: "Failed to create article"})
    end
  end

  def list(conn) do
    params = fetch_query_params(conn).params
    opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
    result = Articles.list(opts)
    send_json(conn, 200, result)
  end

  def show(conn) do
    article_id = conn.path_params["id"]
    
    case Articles.get(article_id) do
      nil -> send_json(conn, 404, %{error: "not_found", message: "Article not found"})
      article -> send_json(conn, 200, serialize_article(article))
    end
  end

  defp create_article(account, params) do
    domain = Application.get_env(:sukhi_fedi, :domain)
    ap_id = "https://#{domain}/articles/#{:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)}"
    
    attrs = %{
      account_id: account.id,
      ap_id: ap_id,
      title: params["title"],
      content: params["content"],
      summary: params["summary"],
      published_at: DateTime.utc_now()
    }
    
    Articles.create(attrs)
  end

  defp serialize_article(article) do
    %{
      id: article.id,
      title: article.title,
      content: article.content,
      summary: article.summary,
      published_at: article.published_at,
      account_id: article.account_id
    }
  end

  defp parse_int(nil, default), do: default
  defp parse_int(str, default) do
    case Integer.parse(str) do
      {int, _} -> int
      _ -> default
    end
  end

  defp authenticate(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> Auth.verify_session(token)
      _ -> {:error, :unauthorized}
    end
  end

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
