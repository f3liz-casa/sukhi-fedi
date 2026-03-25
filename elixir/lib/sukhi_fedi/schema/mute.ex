# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Schema.Mute do
  use Ecto.Schema

  schema "mutes" do
    belongs_to :account, SukhiFedi.Schema.Account
    belongs_to :target, SukhiFedi.Schema.Account
    field :expires_at, :utc_datetime
    timestamps()
  end
end
