# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.ReactionController do
  import Plug.Conn
  alias SukhiFedi.{Repo, Schema, AP, Auth}
  import Ecto.Query

  def add(conn) do
    with {:ok, account} <- authenticate(conn),
         {:ok, body, conn} <- read_body(conn),
         {:ok, params} <- Jason.decode(body),
         note_id <- conn.path_params["id"],
         note <- Repo.get(Schema.Note, note_id),
         true <- note != nil,
         {:ok, reaction} <- create_reaction(account, note, params["emoji"]) do
      
      AP.Client.request("reaction.create", %{
        actor_id: account.id,
        note_id: note.id,
        emoji: params["emoji"]
      })
      
      send_json(conn, 201, serialize_reaction(reaction))
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
      false -> send_json(conn, 404, %{error: "not_found", message: "Note not found"})
      _ -> send_json(conn, 400, %{error: "invalid_request", message: "Failed to create reaction"})
    end
  end

  def remove(conn) do
    with {:ok, account} <- authenticate(conn),
         note_id <- conn.path_params["id"],
         emoji <- URI.decode(conn.path_params["emoji"]),
         reaction <- get_reaction(account.id, note_id, emoji),
         true <- reaction != nil do
      Repo.delete(reaction)
      send_resp(conn, 204, "")
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
      _ -> send_json(conn, 404, %{error: "not_found", message: "Reaction not found"})
    end
  end

  def list(conn) do
    note_id = conn.path_params["id"]
    
    reactions = Schema.Reaction
    |> where([r], r.note_id == ^note_id)
    |> Repo.all()
    |> Repo.preload(:account)
    
    send_json(conn, 200, %{reactions: Enum.map(reactions, &serialize_reaction/1)})
  end

  defp authenticate(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> Auth.verify_session(token)
      _ -> {:error, :unauthorized}
    end
  end

  defp create_reaction(account, note, emoji) do
    %Schema.Reaction{}
    |> Schema.Reaction.changeset(%{
      account_id: account.id,
      note_id: note.id,
      emoji: emoji
    })
    |> Repo.insert()
  end

  defp get_reaction(account_id, note_id, emoji) do
    Schema.Reaction
    |> where([r], r.account_id == ^account_id and r.note_id == ^note_id and r.emoji == ^emoji)
    |> Repo.one()
  end

  defp serialize_reaction(reaction) do
    %{
      id: reaction.id,
      emoji: reaction.emoji,
      account_id: reaction.account_id,
      note_id: reaction.note_id
    }
  end

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
