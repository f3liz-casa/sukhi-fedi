# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.DeliveryReceipt do
  @moduledoc """
  Marks a single (activity_id, inbox_url) delivery as completed.
  Used by the Oban delivery worker for per-inbox idempotency so that
  retries never double-deliver an Activity to the same remote inbox.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "delivery_receipts" do
    field :activity_id, :string
    field :inbox_url, :string
    field :status, :string
    field :delivered_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(receipt, attrs) do
    receipt
    |> cast(attrs, [:activity_id, :inbox_url, :status, :delivered_at])
    |> validate_required([:activity_id, :inbox_url, :status])
    |> validate_inclusion(:status, ["delivered", "failed", "gone"])
    |> unique_constraint([:activity_id, :inbox_url])
  end
end
