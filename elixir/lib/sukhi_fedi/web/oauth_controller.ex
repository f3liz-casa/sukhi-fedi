# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.OAuthController do
  import Plug.Conn
  alias SukhiFedi.{Accounts, Auth}

  def callback(conn) do
    provider = conn.path_params["provider"]
    
    with {:ok, auth} <- Ueberauth.Strategy.handle_callback!(conn),
         uid <- auth.uid,
         account <- Auth.get_account_by_oauth(provider, uid) || create_from_oauth(auth, provider),
         {:ok, token} <- Auth.create_session(account.id) do
      send_json(conn, 200, %{token: token, account_id: account.id})
    else
      _ -> send_json(conn, 401, %{error: "OAuth failed"})
    end
  end

  defp create_from_oauth(auth, provider) do
    username = generate_username(auth.info.nickname || auth.info.email)
    
    {:ok, account} = Accounts.create_account(%{
      username: username,
      display_name: auth.info.name
    })
    
    Auth.link_oauth(account.id, provider, auth.uid)
    account
  end

  defp generate_username(base) do
    base = String.replace(base, ~r/[^a-z0-9_]/, "_")
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{base}_#{suffix}"
  end

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
