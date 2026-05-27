# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.LocalAccounts do
  @moduledoc """
  Create local accounts (the `domain IS NULL` rows). Reachable from
  the api node as `SukhiApi.GatewayRpc.call(SukhiFedi.LocalAccounts,
  :create, [attrs])` from the `POST /api/v1/accounts` capability.

  The signup transaction:

    1. consume the invite code
    2. mint an Ed25519/RSA keypair (the AP actor's own keys)
    3. insert the account row with `domain: nil` and `password_hash`

  If any step fails the whole transaction rolls back, so a failed
  insert won't leave a half-spent invite. Keypair generation uses the
  same `NodeinfoMonitor.KeyGen` helper that seeds bot actors, since
  the shape (`%{public_pem, public_jwk, private_jwk}`) matches what
  the AP actor controller already publishes.
  """

  alias Ecto.Multi
  alias SukhiFedi.Addons.NodeinfoMonitor.KeyGen
  alias SukhiFedi.{InviteCodes, Repo}
  alias SukhiFedi.Schema.Account

  @type signup_attrs :: %{
          required(:username) => String.t(),
          required(:password) => String.t(),
          optional(:email) => String.t() | nil,
          optional(:display_name) => String.t() | nil,
          required(:invite_code) => String.t()
        }

  @spec create(signup_attrs() | map()) ::
          {:ok, Account.t()}
          | {:error, :invite_invalid}
          | {:error, :invite_used}
          | {:error, :invite_expired}
          | {:error, :invite_missing}
          | {:error, :password_too_short}
          | {:error, {:validation, map()}}
  def create(attrs) when is_map(attrs) do
    with {:ok, normalized} <- normalize(attrs),
         {:ok, hash} <- hash_password(normalized.password),
         keys = KeyGen.generate() do
      account_attrs = %{
        username: normalized.username,
        display_name: normalized.display_name || normalized.username,
        email: normalized.email,
        password_hash: hash,
        public_key_pem: keys.public_pem,
        public_key_jwk: keys.public_jwk,
        private_key_jwk: keys.private_jwk
      }

      Multi.new()
      |> Multi.insert(:account, Account.changeset_local(%Account{}, account_attrs))
      |> Multi.run(:invite, fn _repo, %{account: %Account{id: id}} ->
        case InviteCodes.consume(normalized.invite_code, id) do
          {:ok, ic} -> {:ok, ic}
          {:error, :invalid} -> {:error, :invite_invalid}
          {:error, :already_used} -> {:error, :invite_used}
          {:error, :expired} -> {:error, :invite_expired}
        end
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{account: a}} -> {:ok, a}
        {:error, :account, %Ecto.Changeset{} = cs, _} -> {:error, {:validation, errors(cs)}}
        {:error, :invite, reason, _} -> {:error, reason}
        {:error, _step, reason, _} -> {:error, reason}
      end
    end
  end

  defp normalize(attrs) do
    get = fn keys ->
      Enum.find_value(keys, fn k -> Map.get(attrs, k) end)
    end

    username = get.(["username", :username]) |> trim_or_nil()
    password = get.(["password", :password])
    invite = get.(["invite_code", :invite_code, "token", :token]) |> trim_or_nil()
    email = get.(["email", :email]) |> trim_or_nil()
    display_name = get.(["display_name", :display_name]) |> trim_or_nil()

    cond do
      is_nil(invite) -> {:error, :invite_missing}
      is_nil(username) -> {:error, {:validation, %{username: ["を入れてください"]}}}
      true ->
        {:ok,
         %{
           username: String.downcase(username),
           password: password || "",
           invite_code: invite,
           email: email,
           display_name: display_name
         }}
    end
  end

  defp trim_or_nil(nil), do: nil
  defp trim_or_nil(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      v -> v
    end
  end

  defp hash_password(p) when is_binary(p) and byte_size(p) >= 8 do
    {:ok, Argon2.hash_pwd_salt(p)}
  end

  defp hash_password(_), do: {:error, :password_too_short}

  defp errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, options} ->
      Enum.reduce(options, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end

  @doc """
  Verify a username + password against a local account, returning the
  account on match. Used by the `/login` controller before minting a
  session cookie.
  """
  @spec authenticate(String.t(), String.t()) ::
          {:ok, Account.t()} | {:error, :invalid}
  def authenticate(username, password) when is_binary(username) and is_binary(password) do
    case SukhiFedi.Accounts.by_local_username(String.downcase(username)) do
      %Account{password_hash: hash} = a when is_binary(hash) ->
        if Argon2.verify_pass(password, hash), do: {:ok, a}, else: {:error, :invalid}

      _ ->
        # Run the verifier anyway to keep the timing close to a real hit.
        Argon2.no_user_verify()
        {:error, :invalid}
    end
  end

  def authenticate(_, _), do: {:error, :invalid}

  @session_ttl_days 30

  @doc """
  Mint a session row for `account` and return the plaintext token. The
  token is base64url-encoded random bytes; only the SHA-256 hash is
  persisted (same pattern as OAuth access tokens). The caller drops
  the plaintext into a `session_token` cookie.
  """
  @spec create_session(Account.t() | integer()) :: {:ok, String.t()}
  def create_session(%Account{id: id}), do: create_session(id)

  def create_session(account_id) when is_integer(account_id) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(@session_ttl_days * 24 * 60 * 60, :second)
      |> DateTime.truncate(:second)

    {:ok, _} =
      %SukhiFedi.Schema.Session{}
      |> Ecto.Changeset.cast(
        %{token_hash: hash, expires_at: expires_at, account_id: account_id},
        [:token_hash, :expires_at, :account_id]
      )
      |> Repo.insert()

    {:ok, token}
  end
end
