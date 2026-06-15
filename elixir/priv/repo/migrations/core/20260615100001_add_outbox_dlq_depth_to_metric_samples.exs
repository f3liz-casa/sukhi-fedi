# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddOutboxDlqDepthToMetricSamples do
  use Ecto.Migration

  @moduledoc """
  Track the OUTBOX_DLQ depth alongside the host-resource series.

  A non-zero dead-letter queue means outbound federation failed for some
  activities and they're waiting (see `SukhiDelivery.Outbox.PullConsumer`).
  It's NATS JetStream state — not reconstructable from the DB later — so,
  like the host figures, the sampler records it each tick. NULL when the
  stream doesn't exist yet or NATS couldn't be reached.
  """

  def change do
    alter table(:metric_samples) do
      add :outbox_dlq_depth, :integer
    end
  end
end
