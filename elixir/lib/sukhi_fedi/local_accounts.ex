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

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias SukhiFedi.Addons.NodeinfoMonitor.KeyGen
  alias SukhiFedi.{InviteCodes, Repo}
  alias SukhiFedi.Schema.{Account, Session}

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
        private_key_jwk: keys.private_jwk,
        ed25519_private_key_jwk: keys.ed25519_private_jwk,
        ed25519_public_multibase: keys.ed25519_public_multibase
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
        {:error, :account, %Ecto.Changeset{} = cs, _} -> {:error, {:validation, SukhiFedi.Changeset.errors(cs)}}
        {:error, :invite, reason, _} -> {:error, reason}
        {:error, _step, reason, _} -> {:error, reason}
      end
    end
  end

  @doc """
  Create a local account with `is_admin: true`, bypassing the
  invite-code requirement.

  This is the bootstrap door for the very first operator: signup needs
  an invite, and `Accounts.set_admin/3` needs an existing admin to drive
  the back-office UI, so neither can mint the first admin. Reachable as a
  release task — see `SukhiFedi.Release.create_admin/3`.

  `is_admin` is forced on with `put_change`, not cast, so an ordinary
  signup can never smuggle it in through `changeset_local`.
  """
  @spec create_admin(String.t(), String.t(), keyword()) ::
          {:ok, Account.t()}
          | {:error, :password_too_short}
          | {:error, {:validation, map()}}
  def create_admin(username, password, opts \\ [])
      when is_binary(username) and is_binary(password) do
    username = username |> String.trim() |> String.downcase()
    display_name = Keyword.get(opts, :display_name) || username

    with {:ok, hash} <- hash_password(password) do
      keys = KeyGen.generate()

      attrs = %{
        username: username,
        display_name: display_name,
        email: Keyword.get(opts, :email),
        password_hash: hash,
        public_key_pem: keys.public_pem,
        public_key_jwk: keys.public_jwk,
        private_key_jwk: keys.private_jwk,
        ed25519_private_key_jwk: keys.ed25519_private_jwk,
        ed25519_public_multibase: keys.ed25519_public_multibase
      }

      %Account{}
      |> Account.changeset_local(attrs)
      |> Ecto.Changeset.put_change(:is_admin, true)
      |> Repo.insert()
      |> case do
        {:ok, a} -> {:ok, a}
        {:error, cs} -> {:error, {:validation, SukhiFedi.Changeset.errors(cs)}}
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

  @doc """
  Change a local account's password.

  Verifies `current` against the stored hash before swapping in a hash
  of `new`. Returns `{:error, :invalid_current}` if the current password
  doesn't match (with a dummy verify to keep timing even on the account
  that has no hash, e.g. a remote row), or `{:error, :password_too_short}`
  if `new` is under 8 bytes — same floor as signup.

  On success every session for the account is revoked in the same
  transaction, so a changed password logs out all devices (including the
  one that made the change) — they have to sign in again with the new
  password.
  """
  @spec change_password(Account.t(), String.t(), String.t()) ::
          {:ok, Account.t()}
          | {:error, :invalid_current}
          | {:error, :password_too_short}
  def change_password(%Account{id: id, password_hash: hash} = account, current, new)
      when is_binary(current) and is_binary(new) do
    if is_binary(hash) and Argon2.verify_pass(current, hash) do
      case hash_password(new) do
        {:ok, new_hash} ->
          Multi.new()
          |> Multi.update(:account, Ecto.Changeset.change(account, %{password_hash: new_hash}))
          |> Multi.delete_all(:sessions, from(s in Session, where: s.account_id == ^id))
          # Also revoke the account's OAuth bearer tokens, so "change
          # password" actually logs out every API client/device — not just
          # cookie sessions. Otherwise a leaked, never-expiring token kept
          # working after a password change.
          |> Multi.update_all(
            :tokens,
            from(t in SukhiFedi.Schema.OauthAccessToken,
              where: t.account_id == ^id and is_nil(t.revoked_at)
            ),
            set: [revoked_at: DateTime.utc_now() |> DateTime.truncate(:second)]
          )
          |> Repo.transaction()
          |> case do
            {:ok, %{account: a}} -> {:ok, a}
            {:error, _step, reason, _} -> {:error, reason}
          end

        {:error, _} = err ->
          err
      end
    else
      Argon2.no_user_verify()
      {:error, :invalid_current}
    end
  end

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
