# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Admin.InstanceBlocksController do
  @moduledoc "`/admin/instance_blocks` — list, add, remove federation suspensions."

  import Plug.Conn

  alias SukhiFedi.Addons.Moderation
  alias SukhiFedi.Web.Admin.Render

  @page_size 100

  def index(conn) do
    page = parse_page(conn.params["page"])

    {:ok, {blocks, _total}} =
      Moderation.list_instance_blocks(%{
        offset: (page - 1) * @page_size,
        limit: @page_size
      })

    Render.send_page(conn, "instance_blocks/index.html.eex",
      page_title: "Federation blocks",
      blocks: blocks,
      page: page,
      has_next: length(blocks) == @page_size
    )
  end

  def create(conn) do
    domain = (conn.body_params["domain"] || "") |> String.trim() |> String.downcase()
    severity = (conn.body_params["severity"] || "suspend") |> filter_severity()
    reason = (conn.body_params["reason"] || "") |> String.trim()

    cond do
      domain == "" ->
        conn
        |> Render.put_flash(:error, "Domain required.")
        |> redirect("/admin/instance_blocks")

      true ->
        case Moderation.block_instance(domain, severity, reason, conn.assigns.admin.id) do
          {:ok, _} ->
            conn
            |> Render.put_flash(:info, "Blocked #{domain}.")
            |> redirect("/admin/instance_blocks")

          {:error, changeset} ->
            conn
            |> Render.put_flash(:error, "Block failed: #{inspect(changeset.errors)}.")
            |> redirect("/admin/instance_blocks")
        end
    end
  end

  def remove(conn, domain) do
    case Moderation.unblock_instance(domain, conn.assigns.admin.id) do
      {:ok, _} ->
        conn
        |> Render.put_flash(:info, "Unblocked #{domain}.")
        |> redirect("/admin/instance_blocks")

      _ ->
        send_resp(conn, 404, "")
    end
  end

  defp filter_severity(s) when s in ["silence", "suspend"], do: s
  defp filter_severity(_), do: "suspend"

  defp redirect(conn, location) do
    conn
    |> put_resp_header("location", location)
    |> send_resp(302, "")
  end

  defp parse_page(nil), do: 1

  defp parse_page(s) do
    case Integer.parse(to_string(s)) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end
end
