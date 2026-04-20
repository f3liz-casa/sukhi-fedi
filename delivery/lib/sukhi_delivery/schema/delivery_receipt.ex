# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Schema.DeliveryReceipt do
  @moduledoc """
  Per-(activity_id, inbox_url) idempotency marker for outbound deliveries.
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
