# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.Account do
  use Ecto.Schema
  import Ecto.Changeset

  schema "accounts" do
    field :username, :string
    field :display_name, :string
    field :summary, :string
    field :token, :string
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
    field :bio, :string
    field :is_admin, :boolean, default: false
    field :suspended_at, :utc_datetime
    field :suspended_by_id, :id
    field :suspension_reason, :string

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  @doc """
  Changeset for `PATCH /api/v1/accounts/update_credentials`.

  Mastodon allows clients to update display_name, note (we map to
  `summary`), avatar/header URLs, and `bot` flag. We don't expose
  username changes (immutable AP id) and don't accept locked yet
  (no column).
  """
  def changeset_credentials(account, attrs) do
    attrs = normalize_credentials_attrs(attrs)

    account
    |> cast(attrs, [:display_name, :summary, :avatar_url, :banner_url, :bio, :is_bot])
    |> validate_length(:display_name, max: 100)
    |> validate_length(:summary, max: 1024)
  end

  defp normalize_credentials_attrs(attrs) when is_map(attrs) do
    # Accept Mastodon's `note` as an alias for `summary`.
    case Map.get(attrs, "note") || Map.get(attrs, :note) do
      nil -> attrs
      v -> attrs |> Map.put("summary", v) |> Map.delete("note") |> Map.delete(:note)
    end
  end
end
