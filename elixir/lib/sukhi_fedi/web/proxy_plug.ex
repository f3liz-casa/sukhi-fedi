# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.ProxyPlug do
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    deno_url = Application.get_env(:sukhi_fedi, :deno_url, "http://localhost:8000")
    path = "/" <> Enum.join(conn.path_info, "/")
    query = if conn.query_string != "", do: "?" <> conn.query_string, else: ""
    url = deno_url <> path <> query

    {:ok, body, conn} = read_body(conn)

    headers = Enum.reject(conn.req_headers, fn {k, _} -> k in ["host", "content-length"] end)

    case Req.request(
      method: String.downcase(conn.method) |> String.to_atom(),
      url: url,
      headers: headers,
      body: body,
      decode_body: false
    ) do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: resp_body} = response} ->
        headers_list = Map.to_list(resp_headers)
        
        is_streaming = Enum.any?(headers_list, fn 
          {k, [v | _]} -> String.downcase(k) == "x-delegate-to" and String.downcase(v) == "streaming"
          {k, v} when is_binary(v) -> String.downcase(k) == "x-delegate-to" and String.downcase(v) == "streaming"
          _ -> false
        end)

        if is_streaming do
          urn = List.last(conn.path_info)
          conn = %{conn | path_params: Map.put(conn.path_params || %{}, "urn", urn)}
          SukhiFedi.Web.StreamingController.stream(conn)
        else
          # Ensure values are binaries before putting into conn
          normalized_headers = Enum.map(headers_list, fn
            {k, [v | _]} -> {k, v}
            {k, v} -> {k, v}
          end)
          
          conn = %{conn | resp_headers: normalized_headers}
          send_resp(conn, status, resp_body)
        end

      {:error, reason} ->
        Logger.error("Proxy error: #{inspect(reason)}")
        send_resp(conn, 502, "Bad Gateway")
    end
  end
end
