# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Admin.InviteCodesController do
  @moduledoc """
  `/admin/invite_codes` — list existing codes, mint a new one. A code can
  be multi-use (`max_uses` people may join on it) and can be issued *on
  behalf of* another local account: the admin stays recorded as the real
  issuer, but the invite is attributed to — and greets visitors in the
  name of — the represented account.
  """

  alias SukhiFedi.{Accounts, InviteCodes}
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
    params = conn.body_params

    case resolve_on_behalf(params["on_behalf"]) do
      {:error, handle} ->
        conn
        |> Render.put_flash(:error, "@#{handle} というローカルアカウントは見つかりませんでした。")
        |> redirect("/admin/invite_codes")

      {:ok, on_behalf_id} ->
        {:ok, _ic} =
          InviteCodes.issue(admin_id,
            note: params["note"],
            on_behalf_of_id: on_behalf_id,
            max_uses: parse_max_uses(params["max_uses"])
          )

        conn
        |> Render.put_flash(:info, "招待コードを発行しました。")
        |> redirect("/admin/invite_codes")
    end
  end

  # An empty box means "issue in my own name" (no proxy). A non-empty
  # handle must name a real local account — otherwise we'd silently mint a
  # code that greets visitors with a blank.
  defp resolve_on_behalf(raw) do
    case normalize_handle(raw) do
      nil ->
        {:ok, nil}

      handle ->
        case Accounts.by_local_username(handle) do
          %{id: id} -> {:ok, id}
          nil -> {:error, handle}
        end
    end
  end

  defp normalize_handle(nil), do: nil

  defp normalize_handle(s) when is_binary(s) do
    case s |> String.trim() |> String.trim_leading("@") |> String.downcase() do
      "" -> nil
      h -> h
    end
  end

  # Default 1 (single-use). Clamp to at least 1 so an admin's typo can't
  # mint a born-exhausted code.
  defp parse_max_uses(raw) do
    case raw |> to_string() |> String.trim() |> Integer.parse() do
      {n, _} when n >= 1 -> n
      _ -> 1
    end
  end

  defp redirect(conn, location) do
    import Plug.Conn

    conn
    |> put_resp_header("location", location)
    |> send_resp(302, "")
  end
end
