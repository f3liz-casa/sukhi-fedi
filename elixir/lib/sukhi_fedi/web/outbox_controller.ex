# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.OutboxController do
  import Plug.Conn
  import Ecto.Query
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Account, Object}

  def show(conn, _opts) do
    username = conn.path_params["name"]
    
    case Repo.get_by(Account, username: username) do
      nil ->
        send_resp(conn, 404, Jason.encode!(%{error: "not found"}))
      
      account ->
        domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
        actor_uri = "https://#{domain}/users/#{username}"
        
        objects = 
          Object
          |> where([o], o.actor_id == ^actor_uri and o.type in ["Create", "Announce"])
          |> order_by([o], desc: o.created_at)
          |> limit(20)
          |> Repo.all()
        
        outbox = %{
          "@context" => "https://www.w3.org/ns/activitystreams",
          "id" => "#{actor_uri}/outbox",
          "type" => "OrderedCollection",
          "totalItems" => length(objects),
          "orderedItems" => Enum.map(objects, & &1.raw_json)
        }
        
        conn
        |> put_resp_content_type("application/activity+json")
        |> send_resp(200, Jason.encode!(outbox))
    end
  end
end
