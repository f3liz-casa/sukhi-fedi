# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.Account do
  use Ecto.Schema
  import Ecto.Changeset

  schema "accounts" do
    field :username, :string
    field :display_name, :string
    field :summary, :string
    field :emojis, {:array, :map}, default: []
    field :private_key_jwk, :map
    field :public_key_jwk, :map
    # PEM-encoded SubjectPublicKeyInfo — read by actor_controller.ex for
    # ActivityPub actor JSON publication.
    field :public_key_pem, :string
    # Auto-created actors for the NodeInfo monitor bot.
    field :is_bot, :boolean, default: false
    field :monitored_domain, :string
    field :avatar_url, :string
    field :banner_url, :string
    field :is_admin, :boolean, default: false
    # Manual follow approval (Mastodon `locked` / AP
    # `manuallyApprovesFollowers`). For remote rows this mirrors the
    # value from the upstream actor JSON.
    field :locked, :boolean, default: false
    field :suspended_at, :utc_datetime
    field :suspended_by_id, :id
    field :suspension_reason, :string

    # Remote-actor mirror columns. `domain IS NULL` ⇔ local account.
    # For remote rows `actor_uri` is the canonical AP id and `inbox_url`
    # / `shared_inbox_url` come from the actor JSON.
    field :domain, :string
    field :actor_uri, :string
    field :inbox_url, :string
    field :shared_inbox_url, :string
    field :public_key_id, :string
    field :last_fetched_at, :utc_datetime

    # Local-account credentials. Both `domain IS NULL` only. `email`
    # is nullable for now; signup may omit it.
    field :email, :string
    field :password_hash, :string

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  @doc """
  Changeset used by `RemoteAccounts.upsert_from_actor_json/1` to mirror
  a remote actor into the local directory. `domain` must be set
  (NOT NULL ⇔ remote). Idempotent on `actor_uri`.
  """
  def changeset_remote(account, attrs) do
    account
    |> cast(attrs, [
      :username,
      :domain,
      :display_name,
      :summary,
      :emojis,
      :actor_uri,
      :inbox_url,
      :shared_inbox_url,
      :public_key_id,
      :public_key_pem,
      :avatar_url,
      :banner_url,
      :locked,
      :last_fetched_at
    ])
    |> update_change(:summary, &SukhiFedi.HTML.sanitize/1)
    |> validate_required([:username, :domain, :actor_uri])
  end

  @doc """
  Changeset for `PATCH /api/v1/accounts/update_credentials`.

  Mastodon allows clients to update display_name, note (we map to
  `summary`), avatar/header URLs, `bot` flag, and `locked` (manual
  follow approval). We don't expose username changes — the AP id is
  immutable.
  """
  def changeset_credentials(account, attrs) do
    attrs = normalize_credentials_attrs(attrs)

    account
    |> cast(attrs, [:display_name, :summary, :avatar_url, :banner_url, :is_bot, :locked])
    |> update_change(:summary, &SukhiFedi.HTML.sanitize/1)
    |> validate_length(:display_name, max: 100)
    |> validate_length(:summary, max: 1024)
  end

  @doc """
  Changeset for `POST /api/v1/accounts` — local signup. `domain` is
  forced to `nil`; the AP keypair and `public_key_pem` are minted by
  the caller before insert (see `SukhiFedi.LocalAccounts.create/1`).

  `password_hash` is the already-hashed value; raw passwords never
  reach this layer.
  """
  def changeset_local(account, attrs) do
    account
    |> cast(attrs, [
      :username,
      :display_name,
      :email,
      :password_hash,
      :public_key_pem,
      :public_key_jwk,
      :private_key_jwk
    ])
    |> put_change(:domain, nil)
    |> validate_required([:username, :password_hash, :public_key_pem])
    |> validate_format(:username, ~r/^[a-z0-9_]{1,30}$/,
      message: "は小文字英数字とアンダースコアのみ、30字までです"
    )
    |> validate_length(:display_name, max: 100)
    |> unique_constraint(:username, name: :accounts_local_username_index)
  end

  defp normalize_credentials_attrs(attrs) when is_map(attrs) do
    attrs
    |> normalize_alias("note", "summary")
    |> normalize_alias("bot", "is_bot")
  end

  defp normalize_alias(attrs, from, to) do
    case Map.get(attrs, from) || Map.get(attrs, String.to_existing_atom(from)) do
      nil -> attrs
      v -> attrs |> Map.put(to, v) |> Map.delete(from) |> Map.delete(String.to_existing_atom(from))
    end
  rescue
    ArgumentError -> attrs
  end
end
