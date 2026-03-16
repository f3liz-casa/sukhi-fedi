# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.ApiController do
  import Plug.Conn
  alias SukhiFedi.AP.Client
  alias SukhiFedi.Delivery.FanOut
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Account
  alias SukhiFedi.Schema.Object

  def create_account(conn, _opts) do
    %{"username" => username} = conn.body_params
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
          send_resp(conn, 400, Jason.encode!(%{error: inspect(changeset.errors)}))
      end
    else
      {:error, reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: reason}))
    end
  end

  def create_token(conn, _opts) do
    %{"username" => username} = conn.body_params
    case Repo.get_by(Account, username: username) do
      nil ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "account not found"}))
      account ->
        actor_uri = "#{conn.scheme}://#{conn.host}/users/#{username}"
        with {:ok, result} <- Client.request("ap.token.create", %{actorUri: actor_uri}) do
          token = result["token"]
          Repo.update!(Ecto.Changeset.change(account, token: token))
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(201, Jason.encode!(%{token: token}))
        else
          {:error, reason} ->
            send_resp(conn, 400, Jason.encode!(%{error: reason}))
        end
    end
  end

  def create_note(conn, _opts) do
    %{"content" => content, "token" => token} = conn.body_params

    with {:ok, actor} <- Client.request("ap.auth", %{token: token}),
         {:ok, note} <- Client.request("ap.build.note", %{actor: actor, content: content}) do
      object = %Object{
        ap_id: note["id"],
        type: "Note",
        actor_id: actor["id"],
        raw_json: note
      }

      Repo.insert!(object)
      FanOut.enqueue(object, note["recipientInboxes"] || [])

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(201, Jason.encode!(%{id: object.ap_id}))
    else
      {:error, reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: reason}))
    end
  end

  def create_note_cw(conn, _opts) do
    %{"content" => content, "summary" => summary, "token" => token} = conn.body_params
    sensitive = Map.get(conn.body_params, "sensitive", true)

    with {:ok, actor} <- Client.request("ap.auth", %{token: token}),
         {:ok, note} <- Client.request("ap.build.note_cw", %{actor: actor, content: content, summary: summary, sensitive: sensitive}) do
      object = %Object{
        ap_id: note["id"],
        type: "Note",
        actor_id: actor["id"],
        raw_json: note
      }

      Repo.insert!(object)
      FanOut.enqueue(object, note["recipientInboxes"] || [])

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(201, Jason.encode!(%{id: object.ap_id}))
    else
      {:error, reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: reason}))
    end
  end

  def create_boost(conn, _opts) do
    %{"object" => object_url, "token" => token} = conn.body_params

    with {:ok, actor} <- Client.request("ap.auth", %{token: token}),
         {:ok, boost} <- Client.request("ap.build.boost", %{actor: actor, object: object_url}) do
      object = %Object{
        ap_id: boost["id"],
        type: "Announce",
        actor_id: actor["id"],
        raw_json: boost
      }

      Repo.insert!(object)
      FanOut.enqueue(object, boost["recipientInboxes"] || [])

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(201, Jason.encode!(%{id: object.ap_id}))
    else
      {:error, reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: reason}))
    end
  end

  def create_react(conn, _opts) do
    %{"object" => object_url, "emoji" => emoji, "token" => token} = conn.body_params

    with {:ok, actor} <- Client.request("ap.auth", %{token: token}),
         {:ok, react} <- Client.request("ap.build.react", %{actor: actor, object: object_url, emoji: emoji}) do
      object = %Object{
        ap_id: react["id"],
        type: "EmojiReact",
        actor_id: actor["id"],
        raw_json: react
      }

      Repo.insert!(object)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(201, Jason.encode!(%{id: object.ap_id}))
    else
      {:error, reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: reason}))
    end
  end

  def create_quote(conn, _opts) do
    %{"content" => content, "quote_url" => quote_url, "token" => token} = conn.body_params

    with {:ok, actor} <- Client.request("ap.auth", %{token: token}),
         {:ok, note} <- Client.request("ap.build.quote", %{actor: actor, content: content, quoteUrl: quote_url}) do
      object = %Object{
        ap_id: note["id"],
        type: "Note",
        actor_id: actor["id"],
        raw_json: note
      }

      Repo.insert!(object)
      FanOut.enqueue(object, note["recipientInboxes"] || [])

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(201, Jason.encode!(%{id: object.ap_id}))
    else
      {:error, reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: reason}))
    end
  end

  def create_poll(conn, _opts) do
    %{"content" => content, "choices" => choices, "token" => token} = conn.body_params
    multiple = Map.get(conn.body_params, "multiple", false)
    end_time = Map.get(conn.body_params, "end_time")

    with {:ok, actor} <- Client.request("ap.auth", %{token: token}),
         {:ok, poll} <- Client.request("ap.build.poll", %{actor: actor, content: content, choices: choices, multiple: multiple, endTime: end_time}) do
      object = %Object{
        ap_id: poll["id"],
        type: "Question",
        actor_id: actor["id"],
        raw_json: poll
      }

      Repo.insert!(object)
      FanOut.enqueue(object, poll["recipientInboxes"] || [])

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(201, Jason.encode!(%{id: object.ap_id}))
    else
      {:error, reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: reason}))
    end
  end
end
