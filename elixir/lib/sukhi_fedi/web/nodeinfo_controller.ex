# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.NodeinfoController do
  @moduledoc """
  NodeInfo discovery and document endpoints.

  Spec: https://github.com/jhass/nodeinfo

    GET /.well-known/nodeinfo  → discovery JSON with links
    GET /nodeinfo/2.1          → actual NodeInfo 2.1 document

  Pure Elixir — no Deno round-trip. Counts are best-effort Ecto queries;
  they fall back to 0 if the query fails so the endpoint never 500s.
  """

  import Plug.Conn
  import Ecto.Query

  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Account, Note}

  def discovery(conn, _opts) do
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")

    body = %{
      links: [
        %{
          rel: "http://nodeinfo.diaspora.software/ns/schema/2.1",
          href: "https://#{domain}/nodeinfo/2.1"
        }
      ]
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(body))
  end

  def v2_1(conn, _opts) do
    body = %{
      version: "2.1",
      software: %{
        name: "sukhi-fedi",
        version: "0.1.0"
      },
      protocols: ["activitypub"],
      services: %{
        inbound: [],
        outbound: []
      },
      usage: %{
        users: %{
          total: count_safe(Account),
          activeMonth: 0,
          activeHalfyear: 0
        },
        localPosts: count_safe(Note)
      },
      openRegistrations: false,
      metadata: %{}
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(body))
  end

  defp count_safe(queryable) do
    Repo.aggregate(queryable, :count, :id)
  rescue
    _ -> 0
  end
end
