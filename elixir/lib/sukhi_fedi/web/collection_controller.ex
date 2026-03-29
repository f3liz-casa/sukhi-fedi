# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.CollectionController do
  @moduledoc """
  Serves followers and following OrderedCollections for actor profiles.
  Required for FEP-8fcf (Followers Collection Synchronization).
  """

  import Plug.Conn
  import Ecto.Query
  alias SukhiFedi.{Repo, Social}
  alias SukhiFedi.Schema.{Account, Follow}

  def followers(conn, _opts) do
    username = conn.path_params["name"]
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
    actor_uri = "https://#{domain}/users/#{username}"

    account = Repo.get_by(Account, username: username)

    if account do
      items = Social.list_followers(account.id)
      total = length(items)

      collection = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "#{actor_uri}/followers",
        "type" => "OrderedCollection",
        "totalItems" => total,
        "orderedItems" => items
      }

      conn
      |> put_resp_content_type("application/activity+json")
      |> send_resp(200, Jason.encode!(collection))
    else
      send_resp(conn, 404, Jason.encode!(%{error: "not found"}))
    end
  end

  def following(conn, _opts) do
    username = conn.path_params["name"]
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
    actor_uri = "https://#{domain}/users/#{username}"

    account = Repo.get_by(Account, username: username)

    if account do
      follower_uri = actor_uri
      followee_ids = Social.list_following(follower_uri)

      items =
        Enum.map(followee_ids, fn followee_id ->
          case Repo.get(Account, followee_id) do
            %Account{username: u} -> "https://#{domain}/users/#{u}"
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      collection = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "#{actor_uri}/following",
        "type" => "OrderedCollection",
        "totalItems" => length(items),
        "orderedItems" => items
      }

      conn
      |> put_resp_content_type("application/activity+json")
      |> send_resp(200, Jason.encode!(collection))
    else
      send_resp(conn, 404, Jason.encode!(%{error: "not found"}))
    end
  end
end
