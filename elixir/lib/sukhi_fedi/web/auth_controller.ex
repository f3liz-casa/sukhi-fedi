# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.AuthController do
  import Plug.Conn
  alias SukhiFedi.{Accounts, Auth}

  def register(conn) do
    with {:ok, body, conn} <- read_body(conn),
         {:ok, params} <- Jason.decode(body),
         {:ok, account} <- Accounts.create_account(params),
         {:ok, token} <- Auth.create_session(account.id) do
      send_json(conn, 201, %{token: token, account_id: account.id})
    else
      {:error, %Ecto.Changeset{} = changeset} -> 
        send_json(conn, 422, %{error: "validation_error", message: format_errors(changeset)})
      _ -> send_json(conn, 400, %{error: "invalid_request", message: "Bad request"})
    end
  end

  def session(conn) do
    with {:ok, body, conn} <- read_body(conn),
         {:ok, params} <- Jason.decode(body),
         {:ok, account, token} <- authenticate_user(params) do
      send_json(conn, 200, %{token: token, account_id: account.id})
    else
      {:error, :invalid_credentials} -> send_json(conn, 401, %{error: "invalid_credentials", message: "Authentication failed"})
      _ -> send_json(conn, 400, %{error: "invalid_request", message: "Bad request"})
    end
  end

  defp authenticate_user(%{"type" => "passkey", "credential" => credential}) do
    with cred <- Auth.get_webauthn_credential(credential["id"]),
         true <- cred != nil,
         account <- Accounts.get_account(cred.account_id),
         {:ok, token} <- Auth.create_session(account.id) do
      {:ok, account, token}
    else
      _ -> {:error, :invalid_credentials}
    end
  end

  defp authenticate_user(%{"type" => "password", "username" => username, "password" => password}) do
    with account <- Accounts.get_account_by_username(username),
         true <- account != nil,
         true <- Auth.verify_password(account, password),
         {:ok, token} <- Auth.create_session(account.id) do
      {:ok, account, token}
    else
      _ -> {:error, :invalid_credentials}
    end
  end

  defp authenticate_user(_), do: {:error, :invalid_credentials}

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
    |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> Enum.join(", ")
  end

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
