# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.ConversationParticipant do
  use Ecto.Schema
  import Ecto.Changeset

  schema "conversation_participants" do
    field :conversation_ap_id, :string
    field :unread, :boolean, default: false
    belongs_to :account, SukhiFedi.Schema.Account

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  def changeset(cp, attrs) do
    cp
    |> cast(attrs, [:conversation_ap_id, :account_id, :unread])
    |> validate_required([:conversation_ap_id, :account_id])
    |> unique_constraint([:conversation_ap_id, :account_id])
  end
end
