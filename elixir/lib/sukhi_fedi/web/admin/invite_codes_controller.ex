# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Admin.InviteCodesController do
  @moduledoc """
  `/admin/invite_codes` — list existing codes, mint a new one. Codes
  are single-use; once a row's `consumed_at` is set the table just
  shows it as historical evidence of who joined with which invite.
  """

  alias SukhiFedi.InviteCodes
  alias SukhiFedi.Web.Admin.Render

  def index(conn) do
    codes = InviteCodes.list(limit: 100)

    Render.send_page(conn, "invite_codes/index.html.eex",
      page_title: "Invite codes",
      codes: codes
    )
  end

  def create(conn) do
    admin_id = conn.assigns.admin.id
    {:ok, _ic} = InviteCodes.issue(admin_id, note: conn.body_params["note"])

    conn
    |> Render.put_flash(:info, "招待コードを発行しました。")
    |> redirect("/admin/invite_codes")
  end

  defp redirect(conn, location) do
    import Plug.Conn

    conn
    |> put_resp_header("location", location)
    |> send_resp(302, "")
  end
end
