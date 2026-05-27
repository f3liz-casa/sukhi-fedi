# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.Marker do
  use Ecto.Schema
  import Ecto.Changeset

  schema "markers" do
    belongs_to :account, SukhiFedi.Schema.Account
    field :timeline, :string
    field :last_read_id, :string
    field :version, :integer, default: 1
    timestamps()
  end

  @allowed_timelines ~w(home notifications)

  def changeset(marker, attrs) do
    marker
    |> cast(attrs, [:account_id, :timeline, :last_read_id, :version])
    |> validate_required([:account_id, :timeline, :last_read_id])
    |> validate_inclusion(:timeline, @allowed_timelines)
    |> unique_constraint([:account_id, :timeline])
  end
end
