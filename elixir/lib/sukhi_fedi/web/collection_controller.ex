# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.CollectionController do
  @moduledoc """
  Serves followers, following, and outbox OrderedCollections for actor
  profiles. Required for FEP-8fcf (Followers Collection Synchronization)
  and for remote actors / timelines to list an account's public posts.
  """

  import Plug.Conn
  import Ecto.Query
  alias SukhiFedi.{Repo, Social}
  alias SukhiFedi.Schema.{Account, Note}

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

  def outbox(conn, _opts) do
    username = conn.path_params["name"]
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
    actor_uri = "https://#{domain}/users/#{username}"

    account = Repo.get_by(Account, username: username)

    if account do
      notes =
        from(n in Note,
          where: n.account_id == ^account.id and n.visibility == "public",
          order_by: [desc: n.created_at]
        )
        |> Repo.all()

      items = Enum.map(notes, &note_to_create_activity(&1, actor_uri))

      collection = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "#{actor_uri}/outbox",
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

  defp note_to_create_activity(%Note{} = n, actor_uri) do
    note_ap_id = n.ap_id || "#{actor_uri}/notes/#{n.id}"
    activity_id = "#{note_ap_id}/activity"
    published = DateTime.to_iso8601(n.created_at)
    public_ns = "https://www.w3.org/ns/activitystreams#Public"

    %{
      "id" => activity_id,
      "type" => "Create",
      "actor" => actor_uri,
      "published" => published,
      "to" => [public_ns],
      "cc" => ["#{actor_uri}/followers"],
      "object" => %{
        "id" => note_ap_id,
        "type" => "Note",
        "attributedTo" => actor_uri,
        "content" => n.content,
        "published" => published,
        "to" => [public_ns],
        "cc" => ["#{actor_uri}/followers"]
      }
    }
  end

  def following(conn, _opts) do
    username = conn.path_params["name"]
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
    actor_uri = "https://#{domain}/users/#{username}"

    account = Repo.get_by(Account, username: username)

    if account do
      follower_uri = actor_uri

      items =
        follower_uri
        |> Social.list_following()
        |> Enum.map(fn %{username: u} -> "https://#{domain}/users/#{u}" end)

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
