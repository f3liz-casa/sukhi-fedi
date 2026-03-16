# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.ApiController do
  import Plug.Conn

  alias SukhiFedi.AP.Client
  alias SukhiFedi.Delivery.FanOut
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Object

  def create_note(conn, _opts) do
    %{"content" => content, "token" => token} = conn.body_params

    with {:ok, actor} <- Client.request("ap.auth", %{payload: %{token: token}}),
         {:ok, note} <- Client.request("ap.build.note", %{payload: %{actor: actor, content: content}}) do
      object = %Object{
        ap_id: note["id"],
        type: "Note",
        actor_id: actor["id"],
        raw_json: note
      }

      Repo.insert!(object)
      FanOut.enqueue(object, note["recipients"] || [])

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(201, Jason.encode!(%{id: object.ap_id}))
    else
      {:error, reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: reason}))
    end
  end
end
