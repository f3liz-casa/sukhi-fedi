# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.NoteController do
  @moduledoc """
  Serves individual Note objects as AP JSON-LD.

  Remote servers dereference a Note id to hydrate the object after
  receiving a Create activity that only referenced it, and to refresh
  a cached copy. Without this endpoint the note shows up in the
  recipient's inbox but is dropped or rendered as broken on timelines
  (observed on iceshrimp → watcher-hackers_pub: "1 posts" on the
  profile but the posts tab stays empty).
  """

  import Plug.Conn
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Account, Note}

  def show(conn, _opts) do
    username = conn.path_params["name"]
    note_id_raw = conn.path_params["note_id"]
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
    actor_uri = "https://#{domain}/users/#{username}"

    with {note_id, ""} <- Integer.parse(note_id_raw || ""),
         %Account{id: aid} <- Repo.get_by(Account, username: username),
         %Note{} = note <- Repo.get(Note, note_id),
         true <- note.account_id == aid,
         true <- note.visibility == "public" do
      send_json(conn, 200, note_to_ap(note, actor_uri))
    else
      _ -> send_json(conn, 404, %{error: "not found"})
    end
  end

  defp note_to_ap(%Note{} = n, actor_uri) do
    public_ns = "https://www.w3.org/ns/activitystreams#Public"

    %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => "#{actor_uri}/notes/#{n.id}",
      "type" => "Note",
      "attributedTo" => actor_uri,
      "content" => n.content,
      "published" => DateTime.to_iso8601(n.created_at),
      "to" => [public_ns],
      "cc" => ["#{actor_uri}/followers"]
    }
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/activity+json")
    |> send_resp(status, Jason.encode!(body))
  end
end
