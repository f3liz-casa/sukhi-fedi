# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Admin.ReportsController do
  @moduledoc "`/admin/reports` — open / resolved queues, resolve action."

  import Plug.Conn

  alias SukhiFedi.Addons.Moderation
  alias SukhiFedi.Web.Admin.Render

  @page_size 50

  def index(conn) do
    status = (conn.params["status"] || "open") |> filter_status()
    page = parse_page(conn.params["page"])

    {:ok, {reports, _total}} =
      Moderation.list_reports(status, %{
        offset: (page - 1) * @page_size,
        limit: @page_size
      })

    Render.send_page(conn, "reports/index.html.eex",
      page_title: "Reports",
      reports: reports,
      status: status,
      page: page,
      has_next: length(reports) == @page_size
    )
  end

  def resolve(conn, id) do
    with {n, ""} <- Integer.parse(to_string(id)),
         {:ok, report} <- Moderation.resolve_report(n, conn.assigns.admin.id) do
      Render.send_fragment(conn, "reports/_row.html.eex", report: report)
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  defp filter_status(s) when s in ["open", "resolved"], do: s
  defp filter_status(_), do: "open"

  defp parse_page(nil), do: 1

  defp parse_page(s) do
    case Integer.parse(to_string(s)) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end
end
