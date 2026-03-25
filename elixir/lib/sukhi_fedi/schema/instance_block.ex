# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Schema.InstanceBlock do
  use Ecto.Schema

  schema "instance_blocks" do
    field :domain, :string
    field :severity, :string
    field :reason, :string
    belongs_to :created_by, SukhiFedi.Schema.Account
    timestamps()
  end
end
