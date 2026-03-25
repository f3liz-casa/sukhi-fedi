# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.NotesController do
  import Plug.Conn
  alias SukhiFedi.{Notes, Auth, Accounts}

  def create(conn) do
    with {:ok, account} <- authenticate(conn),
         {:ok, body, conn} <- read_body(conn),
         {:ok, params} <- Jason.decode(body),
         {:ok, note} <- handle_create(account, params) do
      publish_new_post(note, account)
      send_json(conn, 201, serialize_note(note))
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
      {:error, msg} when is_binary(msg) -> send_json(conn, 422, %{error: "validation_error", message: msg})
      _ -> send_json(conn, 400, %{error: "invalid_request", message: "Bad request"})
    end
  end

  def show(conn) do
    note_id = conn.path_params["id"]
    
    case Notes.get_note(note_id) do
      nil -> send_json(conn, 404, %{error: "not_found", message: "Note not found"})
      note -> send_json(conn, 200, serialize_note(note))
    end
  end

  def list_by_user(conn) do
    username = conn.path_params["username"]
    
    case Accounts.get_account_by_username(username) do
      nil -> send_json(conn, 404, %{error: "not_found", message: "User not found"})
      account ->
        params = fetch_query_params(conn).params
        opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
        result = Notes.list_notes_by_account(account.id, opts)
        send_json(conn, 200, result)
    end
  end

  def like(conn) do
    with {:ok, account} <- authenticate(conn),
         note_id <- conn.path_params["id"],
         note <- Notes.get_note(note_id),
         true <- note != nil,
         {:ok, _} <- Notes.create_like(account.id, note_id) do
      send_json(conn, 201, %{success: true})
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
      false -> send_json(conn, 404, %{error: "not_found", message: "Note not found"})
      _ -> send_json(conn, 400, %{error: "invalid_request", message: "Failed to like"})
    end
  end

  def unlike(conn) do
    with {:ok, account} <- authenticate(conn),
         note_id <- conn.path_params["id"],
         :ok <- Notes.delete_like(account.id, note_id) do
      send_resp(conn, 204, "")
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
      _ -> send_json(conn, 404, %{error: "not_found", message: "Like not found"})
    end
  end

  def delete(conn) do
    with {:ok, account} <- authenticate(conn),
         note_id <- conn.path_params["id"],
         note <- Notes.get_note(note_id),
         true <- note != nil and note.account_id == account.id,
         {:ok, _} <- Notes.delete_note(note) do
      send_resp(conn, 204, "")
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
      false -> send_json(conn, 403, %{error: "forbidden", message: "Cannot delete this note"})
      _ -> send_json(conn, 404, %{error: "not_found", message: "Note not found"})
    end
  end

  defp handle_create(account, %{"type" => "Note"} = params) do
    attrs = %{
      "account_id" => account.id,
      "content" => params["text"],
      "visibility" => params["visibility"] || "public",
      "cw" => params["cw"],
      "mfm" => params["mfm"]
    }
    
    with {:ok, note} <- Notes.create_note(attrs),
         :ok <- attach_media(note, params["media_ids"]),
         :ok <- create_poll(note, params["poll"]) do
      {:ok, note}
    end
  end

  defp handle_create(account, %{"type" => "Boost", "renote_id" => renote_id}) do
    case Notes.get_note(renote_id) do
      nil -> {:error, "Note to boost not found"}
      _note -> Notes.create_boost(account.id, renote_id)
    end
  end

  defp handle_create(account, %{"type" => "Article"} = params) do
    attrs = %{
      "account_id" => account.id,
      "title" => params["title"],
      "content" => params["text"],
      "summary" => params["summary"]
    }
    Notes.create_article(attrs)
  end

  defp handle_create(_account, _params), do: {:error, "Invalid note type"}

  defp parse_int(nil, default), do: default
  defp parse_int(str, default) do
    case Integer.parse(str) do
      {int, _} -> int
      _ -> default
    end
  end

  defp authenticate(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> Auth.verify_session(token)
      _ -> {:error, :unauthorized}
    end
  end

  defp serialize_note(note) do
    %{
      id: note.id,
      content: note.content,
      visibility: note.visibility,
      cw: note.cw,
      mfm: note.mfm,
      created_at: note.created_at,
      account_id: note.account_id
    }
  end

  defp attach_media(_note, nil), do: :ok
  defp attach_media(note, media_ids) when is_list(media_ids) do
    SukhiFedi.Media.attach_to_note(note.id, media_ids)
    :ok
  end

  defp create_poll(_note, nil), do: :ok
  defp create_poll(note, %{"options" => options, "expires_at" => expires_at, "multiple" => multiple}) do
    {:ok, poll} = SukhiFedi.Repo.insert(%SukhiFedi.Schema.Poll{
      note_id: note.id,
      expires_at: expires_at,
      multiple: multiple
    })
    
    options
    |> Enum.with_index()
    |> Enum.each(fn {title, idx} ->
      SukhiFedi.Repo.insert(%SukhiFedi.Schema.PollOption{
        poll_id: poll.id,
        title: title,
        position: idx
      })
    end)
    
    :ok
  end
  defp create_poll(_note, _), do: :ok

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  defp publish_new_post(note, account) do
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
    actor_id = "https://#{domain}/users/#{account.username}"
    
    payload = %{
      object: serialize_note(note),
      actor_id: actor_id
    }
    
    case Jason.encode(payload) do
      {:ok, json} -> Gnat.pub(:gnat, "stream.new_post", json)
      _ -> :ok
    end
  end
end
