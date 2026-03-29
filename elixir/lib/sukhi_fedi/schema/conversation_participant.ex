# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Schema.ConversationParticipant do
  use Ecto.Schema
  import Ecto.Changeset

  schema "conversation_participants" do
    field :conversation_ap_id, :string
    belongs_to :account, SukhiFedi.Schema.Account
    field :created_at, :utc_datetime, autogenerate: {DateTime, :utc_now, []}
  end

  def changeset(cp, attrs) do
    cp
    |> cast(attrs, [:conversation_ap_id, :account_id])
    |> validate_required([:conversation_ap_id, :account_id])
    |> unique_constraint([:conversation_ap_id, :account_id])
  end
end
