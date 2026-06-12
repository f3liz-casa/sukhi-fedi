# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Auth.SignupEmailController do
  @moduledoc """
  The mailbox round-trip *before* an account exists:

      POST /signup/email/request   {email}        → code mail
      POST /signup/email/confirm   {email, code}  → {email_proof}

  The proof is a signed 20-minute token the signup form then carries
  into `POST /api/v1/accounts` — accounts are born with a verified
  address, which is what lets the password be optional. Unlike the
  login door, `request` here *does* say `email_taken` out loud: the
  form needs to tell people to pick another address, and "taken"
  only reveals verified owners (who chose to be reachable there).
  """

  import Plug.Conn

  alias SukhiFedi.Auth.EmailAuth

  def request(conn) do
    email = to_string(conn.body_params["email"] || "")

    case EmailAuth.request_signup_code(email) do
      :ok -> json(conn, 200, %{ok: true})
      {:error, :invalid_email} -> json(conn, 422, %{error: "email"})
      {:error, :email_taken} -> json(conn, 422, %{error: "email_taken"})
      {:error, :rate_limited} -> json(conn, 429, %{error: "rate_limited"})
      {:error, :send_failed} -> json(conn, 502, %{error: "send_failed"})
    end
  end

  def confirm(conn) do
    email = to_string(conn.body_params["email"] || "")
    code = to_string(conn.body_params["code"] || "")

    case EmailAuth.confirm_signup_code(email, code) do
      {:ok, proof} -> json(conn, 200, %{ok: true, email_proof: proof})
      {:error, :expired} -> json(conn, 422, %{error: "expired"})
      {:error, :too_many_attempts} -> json(conn, 429, %{error: "too_many_attempts"})
      {:error, :invalid_code} -> json(conn, 422, %{error: "code"})
    end
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(data))
  end
end
