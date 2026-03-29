# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.Block do
  use Ecto.Schema

  schema "blocks" do
    belongs_to :account, SukhiFedi.Schema.Account
    belongs_to :target, SukhiFedi.Schema.Account
    timestamps()
  end
end
