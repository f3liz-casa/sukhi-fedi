# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.ApiController do
  import Plug.Conn
  alias SukhiFedi.AP.Client
  alias SukhiFedi.Delivery.FanOut
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Account
  alias SukhiFedi.Schema.Object

  def create_account(conn, _opts) do
    with {:ok, username} <- Map.fetch(conn.body_params, "username") do
      display_name = Map.get(conn.body_params, "display_name")
      summary = Map.get(conn.body_params, "summary")
      base_url = "#{conn.scheme}://#{conn.host}"
      actor_uri = "#{base_url}/users/#{username}"
      key_id = "#{actor_uri}#main-key"
      inbox_uri = "#{base_url}/users/#{username}/inbox"

      with {:ok, result} <- Client.request("ap.account.create", %{
                              username: username,
                              displayName: display_name,
                              summary: summary,
                              actorUri: actor_uri,
                              keyId: key_id,
                              inboxUri: inbox_uri
                            }) do
        account = %Account{
          username: username,
          display_name: display_name,
          summary: summary,
          private_key_jwk: result["privateKeyJwk"],
          public_key_jwk: result["publicKeyJwk"]
        }

        case Repo.insert(account) do
          {:ok, inserted} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(201, Jason.encode!(%{id: inserted.id, username: inserted.username, actor_uri: actor_uri}))

          {:error, changeset} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(400, Jason.encode!(%{error: inspect(changeset.errors)}))
        end
      else
        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(400, Jason.encode!(%{error: reason}))
      end
    else
      :error ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "missing required fields"}))
    end
  end

  def create_token(conn, _opts) do
    with {:ok, username} <- Map.fetch(conn.body_params, "username") do
      case Repo.get_by(Account, username: username) do
        nil ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(404, Jason.encode!(%{error: "account not found"}))

        account ->
          actor_uri = "#{conn.scheme}://#{conn.host}/users/#{username}"

          with {:ok, result} <- Client.request("ap.token.create", %{actorUri: actor_uri}) do
            token = result["token"]

            case Repo.update(Ecto.Changeset.change(account, token: token)) do
              {:ok, _} ->
                conn
                |> put_resp_content_type("application/json")
                |> send_resp(201, Jason.encode!(%{token: token}))

              {:error, _} ->
                conn
                |> put_resp_content_type("application/json")
                |> send_resp(500, Jason.encode!(%{error: "failed to save token"}))
            end
          else
            {:error, reason} ->
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(400, Jason.encode!(%{error: reason}))
          end
      end
    else
      :error ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "missing required fields"}))
    end
  end

  def create_note(conn, _opts),
    do: create_ap_object(conn, ["content"], "ap.build.note", "Note")

  def create_note_cw(conn, _opts),
    do: create_ap_object(conn, ["content", "summary"], "ap.build.note_cw", "Note")

  def create_boost(conn, _opts),
    do: create_ap_object(conn, ["object"], "ap.build.boost", "Announce")

  def create_react(conn, _opts),
    do: create_ap_object(conn, ["object", "emoji"], "ap.build.react", "EmojiReact")

  def create_quote(conn, _opts),
    do: create_ap_object(conn, ["content", "quote_url"], "ap.build.quote", "Note")

  def create_poll(conn, _opts),
    do: create_ap_object(conn, ["content", "choices"], "ap.build.poll", "Question")

  defp create_ap_object(conn, required_keys, build_topic, object_type) do
    params = conn.body_params

    with {:ok, token} <- Map.fetch(params, "token"),
         :ok <- check_required(params, required_keys),
         {:ok, actor} <- Client.request("ap.auth", %{token: token}),
         build_payload = Map.merge(%{"actor" => actor}, Map.take(params, required_keys)),
         {:ok, built} <- Client.request(build_topic, build_payload),
         object = %Object{
           ap_id: built["id"],
           type: object_type,
           actor_id: actor["id"],
           raw_json: built
         },
         {:ok, inserted} <- Repo.insert(object) do
      FanOut.enqueue(inserted, built["recipientInboxes"] || [])

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(201, Jason.encode!(%{id: inserted.ap_id}))
    else
      :error ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "missing required fields"}))

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(409, Jason.encode!(%{error: inspect(cs.errors)}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: reason}))
    end
  end

  defp check_required(params, keys) do
    if Enum.all?(keys, &Map.has_key?(params, &1)), do: :ok, else: :error
  end
end
