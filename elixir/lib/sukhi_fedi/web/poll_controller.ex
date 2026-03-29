# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.PollController do
  import Plug.Conn
  alias SukhiFedi.{Repo, Schema, Auth}
  import Ecto.Query

  def vote(conn) do
    with {:ok, account} <- authenticate(conn),
         {:ok, body, conn} <- read_body(conn),
         {:ok, params} <- Jason.decode(body),
         note_id <- conn.path_params["id"],
         note <- Repo.get(Schema.Note, note_id) |> Repo.preload(:poll),
         true <- note != nil and note.poll != nil,
         poll <- Repo.preload(note.poll, :options),
         true <- valid_choices?(poll, params["choices"]),
         {:ok, _} <- create_votes(account.id, poll, params["choices"]) do
      send_json(conn, 201, %{success: true})
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
      false -> send_json(conn, 400, %{error: "invalid_request", message: "Invalid poll or choices"})
      _ -> send_json(conn, 400, %{error: "invalid_request", message: "Failed to vote"})
    end
  end

  defp authenticate(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> Auth.verify_session(token)
      _ -> {:error, :unauthorized}
    end
  end

  defp valid_choices?(poll, choices) when is_list(choices) do
    max_index = length(poll.options) - 1
    Enum.all?(choices, fn choice -> choice >= 0 and choice <= max_index end)
  end
  defp valid_choices?(_poll, _), do: false

  defp create_votes(account_id, poll, choices) do
    # Check if already voted
    existing = Schema.PollVote
    |> where([v], v.account_id == ^account_id and v.poll_id == ^poll.id)
    |> Repo.all()

    if length(existing) > 0 and not poll.multiple do
      {:error, :already_voted}
    else
      Enum.each(choices, fn choice_idx ->
        option = Enum.at(poll.options, choice_idx)
        %Schema.PollVote{}
        |> Schema.PollVote.changeset(%{
          account_id: account_id,
          poll_id: poll.id,
          option_id: option.id
        })
        |> Repo.insert()
      end)
      {:ok, :voted}
    end
  end

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
