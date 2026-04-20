# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.ActorController do
  import Plug.Conn
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Account

  def show(conn, _opts) do
    username = conn.path_params["name"]
    
    case Repo.get_by(Account, username: username) do
      nil ->
        send_resp(conn, 404, Jason.encode!(%{error: "not found"}))
      
      account ->
        domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
        actor_uri = "https://#{domain}/users/#{username}"
        
        actor = %{
          "@context" => [
            "https://www.w3.org/ns/activitystreams",
            "https://w3id.org/security/v1",
            %{"featured" => %{"@id" => "toot:featured", "@type" => "@id"}, "toot" => "http://joinmastodon.org/ns#"}
          ],
          "id" => actor_uri,
          "type" => "Person",
          "preferredUsername" => username,
          "name" => account.display_name || username,
          "summary" => account.summary || "",
          "inbox" => "#{actor_uri}/inbox",
          "outbox" => "#{actor_uri}/outbox",
          "followers" => "#{actor_uri}/followers",
          "following" => "#{actor_uri}/following",
          "featured" => "#{actor_uri}/featured",
          "publicKey" => %{
            "id" => "#{actor_uri}#main-key",
            "owner" => actor_uri,
            "publicKeyPem" => account.public_key_pem || ""
          }
        }
        
        conn
        |> put_resp_content_type("application/activity+json")
        |> send_resp(200, Jason.encode!(actor))
    end
  end
end
