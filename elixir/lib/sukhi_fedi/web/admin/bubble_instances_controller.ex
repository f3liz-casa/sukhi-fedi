# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Admin.BubbleInstancesController do
  @moduledoc """
  `/admin/bubble_instances` — curate the bubble (ご近所) timeline's
  allow-list. Add a trusted remote host by hand, or search the hosts we
  already federate with and add one with a click. The mirror of
  `instance_blocks`, but an allow-list rather than a block-list.
  """

  import Plug.Conn

  alias SukhiFedi.Addons.Moderation
  alias SukhiFedi.Web.Admin.Render

  def index(conn) do
    q = conn.params["q"]
    current = Moderation.list_bubble_instances()
    current_domains = MapSet.new(current, & &1.domain)

    # Only search when the admin typed something — the bubble is small and
    # curated, so we don't dump the whole peer list by default. Hosts already
    # in the bubble drop out of the suggestions (no point offering a dup).
    suggestions =
      case q do
        nil -> []
        _ -> Enum.reject(Moderation.known_domains(q, limit: 50), &MapSet.member?(current_domains, &1))
      end

    Render.send_page(conn, "bubble_instances/index.html.eex",
      page_title: "Bubble",
      current: current,
      suggestions: suggestions,
      q: q || "",
      searched: not is_nil(q)
    )
  end

  def create(conn) do
    domain = (conn.body_params["domain"] || "") |> String.trim() |> String.downcase()

    cond do
      domain == "" ->
        conn
        |> Render.put_flash(:error, "Domain required.")
        |> redirect("/admin/bubble_instances")

      true ->
        case Moderation.add_bubble_instance(domain, conn.assigns.admin.id) do
          {:ok, _} ->
            conn
            |> Render.put_flash(:info, "Added #{domain} to the bubble.")
            |> redirect("/admin/bubble_instances")

          {:error, reason} ->
            conn
            |> Render.put_flash(:error, "Add failed: #{inspect(reason)}.")
            |> redirect("/admin/bubble_instances")
        end
    end
  end

  def remove(conn, domain) do
    case Moderation.remove_bubble_instance(domain, conn.assigns.admin.id) do
      {:ok, _} ->
        conn
        |> Render.put_flash(:info, "Removed #{domain} from the bubble.")
        |> redirect("/admin/bubble_instances")

      _ ->
        send_resp(conn, 404, "")
    end
  end

  defp redirect(conn, location) do
    conn
    |> put_resp_header("location", location)
    |> send_resp(302, "")
  end
end
