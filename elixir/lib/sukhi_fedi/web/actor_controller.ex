# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.ActorController do
  import Plug.Conn

  def show(conn, _opts) do
    username = conn.path_params["name"]

    case SukhiFedi.Accounts.by_local_username(username) do
      nil ->
        send_resp(conn, 404, JSON.encode!(%{error: "not found"}))

      account ->
        # Use the single source of truth so icon / image / endpoints /
        # publicKey stay in lockstep with the Update(Person) body that
        # delivery fans out. Before this collapse, the inline map here
        # was missing icon/image entirely and avatars never federated.
        actor = SukhiFedi.AP.ActorJson.build_person(account)

        conn
        |> put_resp_content_type("application/activity+json")
        |> send_resp(200, JSON.encode!(actor))
    end
  end
end
