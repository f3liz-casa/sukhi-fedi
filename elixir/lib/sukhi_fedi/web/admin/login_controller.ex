# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Admin.LoginController do
  @moduledoc """
  `/admin/login` — paste-a-bearer-token login form.

  The admin obtains a Mastodon OAuth token through any standard flow
  (Mastodon client, programmatic `/oauth/token` call, mix task on the
  server). We do not handle the OAuth dance here; just accept a
  pre-issued token and verify it. v1 trade-off: skip building an
  authorize-bounce UI when this is faster.
  """

  import Plug.Conn

  alias SukhiFedi.OAuth
  alias SukhiFedi.Web.Admin.Render

  def show(conn) do
    Render.send_page(conn, "login.html.eex", page_title: "Sign in")
  end

  def submit(conn) do
    token = conn.body_params["token"] |> to_string() |> String.trim()

    cond do
      token == "" ->
        conn
        |> Render.put_flash(:error, "Token can't be empty.")
        |> redirect("/admin/login")

      true ->
        case OAuth.verify_bearer(token) do
          {:ok, %{account: %{is_admin: true}}} ->
            conn
            |> put_session(:bearer, token)
            |> redirect("/admin")

          {:ok, %{account: %{is_admin: false}}} ->
            conn
            |> Render.put_flash(:error, "That token belongs to a non-admin account.")
            |> redirect("/admin/login")

          {:error, reason} ->
            conn
            |> Render.put_flash(:error, "Token rejected: #{reason}.")
            |> redirect("/admin/login")
        end
    end
  end

  def logout(conn) do
    conn
    |> configure_session(drop: true)
    |> redirect("/admin/login")
  end

  defp redirect(conn, location) do
    conn
    |> put_resp_header("location", location)
    |> send_resp(302, "")
  end
end
