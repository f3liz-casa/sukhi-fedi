# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Auth do
  import Ecto.Query
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Account, Session, WebauthnCredential, OauthConnection}

  @session_ttl_hours 24 * 7

  def create_session(account_id) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    token_hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
    
    expires_at = DateTime.utc_now() |> DateTime.add(@session_ttl_hours, :hour)
    
    %Session{}
    |> Ecto.Changeset.change(%{
      account_id: account_id,
      token_hash: token_hash,
      expires_at: expires_at
    })
    |> Repo.insert()
    |> case do
      {:ok, _session} -> {:ok, token}
      error -> error
    end
  end

  def verify_session(token) do
    token_hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
    
    query = from s in Session,
      where: s.token_hash == ^token_hash and s.expires_at > ^DateTime.utc_now(),
      preload: :account
    
    case Repo.one(query) do
      nil -> {:error, :invalid_token}
      session -> {:ok, session.account}
    end
  end

  def verify_token(token) do
    case verify_session(token) do
      {:ok, account} -> {:ok, account.id}
      error -> error
    end
  end

  def current_account(conn) do
    case get_auth_token(conn) do
      nil -> {:error, :unauthorized}
      token -> verify_session(token)
    end
  end

  defp get_auth_token(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end

  def delete_session(token) do
    token_hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
    
    from(s in Session, where: s.token_hash == ^token_hash)
    |> Repo.delete_all()
    
    :ok
  end

  def register_webauthn_credential(account_id, credential_id, public_key) do
    %WebauthnCredential{}
    |> Ecto.Changeset.change(%{
      account_id: account_id,
      credential_id: credential_id,
      public_key: public_key,
      sign_count: 0
    })
    |> Repo.insert()
  end

  def get_webauthn_credential(credential_id) do
    Repo.get_by(WebauthnCredential, credential_id: credential_id)
  end

  def update_webauthn_sign_count(credential, sign_count) do
    credential
    |> Ecto.Changeset.change(%{sign_count: sign_count})
    |> Repo.update()
  end

  def link_oauth(account_id, provider, provider_uid) do
    %OauthConnection{}
    |> Ecto.Changeset.change(%{
      account_id: account_id,
      provider: provider,
      provider_uid: provider_uid
    })
    |> Repo.insert()
  end

  def get_account_by_oauth(provider, provider_uid) do
    query = from o in OauthConnection,
      where: o.provider == ^provider and o.provider_uid == ^provider_uid,
      preload: :account
    
    case Repo.one(query) do
      nil -> nil
      conn -> conn.account
    end
  end
end
