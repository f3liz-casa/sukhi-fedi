# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.FeaturedController do
  @moduledoc """
  Serves the featured (pinned posts) OrderedCollection for an actor.
  Required for Mastodon-compatible featured posts and FEP-e232.
  """

  import Plug.Conn
  alias SukhiFedi.PinnedNotes

  def show(conn, _opts) do
    username = conn.path_params["name"]
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
    actor_uri = "https://#{domain}/users/#{username}"

    notes = PinnedNotes.list_for_username(username)

    items =
      Enum.map(notes, fn note ->
        note.ap_id || "https://#{domain}/notes/#{note.id}"
      end)

    collection = %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => "#{actor_uri}/featured",
      "type" => "OrderedCollection",
      "totalItems" => length(items),
      "orderedItems" => items
    }

    conn
    |> put_resp_content_type("application/activity+json")
    |> send_resp(200, Jason.encode!(collection))
  end
end
