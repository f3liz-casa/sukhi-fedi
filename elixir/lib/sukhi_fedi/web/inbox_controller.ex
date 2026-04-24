# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.InboxController do
  import Plug.Conn

  alias SukhiFedi.AP.Instructions
  alias SukhiFedi.Federation.FedifyClient
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Account

  # FEP-8fcf Collection-Synchronization format:
  #   collectionId="<uri>", url="<uri>", digest="<hex>"
  @sync_url_regex ~r/url="([^"]+)"/

  @follower_sync_worker "SukhiDelivery.Delivery.FollowerSyncWorker"
  @follower_sync_queue "federation"

  def user_inbox(conn, _opts) do
    handle_inbox(conn)
  end

  def shared_inbox(conn, _opts) do
    handle_inbox(conn)
  end

  defp handle_inbox(conn) do
    raw_json = conn.body_params
    raw_body = conn.assigns[:raw_body] || ""
    headers = Enum.into(conn.req_headers, %{})
    url = public_url(conn)
    sync_header = get_req_header(conn, "collection-synchronization") |> List.first()

    verify_payload = %{
      raw: raw_body,
      headers: headers,
      method: "POST",
      url: url
    }

    self_domain = Application.get_env(:sukhi_fedi, :domain) || conn.host

    inbox_payload =
      case sign_as_for(conn) do
        nil -> %{raw: raw_json, selfDomain: self_domain}
        sign_as -> %{raw: raw_json, signAs: sign_as, selfDomain: self_domain}
      end

    with {:ok, _} <- FedifyClient.verify(verify_payload),
         {:ok, instruction} <- FedifyClient.inbox(inbox_payload) do
      Instructions.execute(instruction)
      maybe_enqueue_follower_sync(raw_json, sync_header)
      send_resp(conn, 202, "")
    else
      {:error, reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: inspect(reason)}))
    end
  end

  # Reconstruct the public URL the remote signer signed against, even
  # when cloudflared (or any reverse proxy) has rewritten Host to an
  # internal value like `gateway:4000`.
  defp public_url(conn) do
    domain = Application.get_env(:sukhi_fedi, :domain) || conn.host
    query = if conn.query_string in [nil, ""], do: "", else: "?" <> conn.query_string
    "https://#{domain}#{conn.request_path}#{query}"
  end

  # When the inbox is user-scoped (`/users/:name/inbox`), return the
  # receiving account's signing key so Bun's `getActor` call can do an
  # authorized (signed) fetch of the remote actor. Required by servers
  # with Secure Mode / authorized-fetch turned on (Mastodon, Misskey).
  # Shared inbox has no :name, so this returns nil.
  defp sign_as_for(conn) do
    domain = Application.get_env(:sukhi_fedi, :domain) || conn.host

    with username when is_binary(username) <- conn.path_params["name"],
         %Account{private_key_jwk: priv, public_key_jwk: pub} when not is_nil(priv) <-
           Repo.get_by(Account, username: username) do
      %{
        keyId: "https://#{domain}/users/#{username}#main-key",
        privateJwk: priv,
        publicJwk: pub
      }
    else
      _ -> nil
    end
  end

  defp maybe_enqueue_follower_sync(_raw_json, nil), do: :ok

  defp maybe_enqueue_follower_sync(raw_json, sync_header) do
    actor_uri = Map.get(raw_json, "actor")

    with true <- is_binary(actor_uri),
         [_, collection_url] <- Regex.run(@sync_url_regex, sync_header) do
      Oban.insert(
        SukhiFedi.Oban,
        Oban.Job.new(
          %{actor_uri: actor_uri, collection_url: collection_url},
          worker: @follower_sync_worker,
          queue: @follower_sync_queue
        )
      )
    end

    :ok
  end
end
