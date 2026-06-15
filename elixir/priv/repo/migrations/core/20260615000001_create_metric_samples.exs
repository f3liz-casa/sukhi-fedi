# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateMetricSamples do
  use Ecto.Migration

  @moduledoc """
  A time series of host-resource snapshots, one row per sampler tick.

  Host CPU / memory / load / disk and the BEAM's own footprint are
  ephemeral — `:os_mon` only ever reports *now*, and the SSE stream
  throws each reading away. To analyse trends (anomaly baselines,
  capacity forecasting) something has to keep them. This table is that
  store, written by `SukhiFedi.Metrics.Sampler` and read back as JSON
  through `/api/metrics?since=`.

  Deliberately narrow: only what cannot be reconstructed later. Account
  and status growth already lives in the DB with timestamps, so it is
  *not* duplicated here — Julia can recover those curves from `notes`
  / `accounts` directly.
  """

  def change do
    create table(:metric_samples) do
      add :sampled_at, :utc_datetime_usec, null: false

      add :cpu_percent, :float
      add :load1, :float
      add :load5, :float
      add :load15, :float

      add :mem_total, :bigint
      add :mem_used, :bigint
      add :mem_available, :bigint
      add :swap_total, :bigint
      add :swap_free, :bigint

      add :beam_total, :bigint
      add :beam_processes, :bigint
      add :beam_binary, :bigint

      add :disk_total, :bigint
      add :disk_used_percent, :float
    end

    # Every read is a window query ordered by time (`?since=`/`?until=`)
    # and the retention sweep deletes the oldest rows — both ride this
    # index.
    create index(:metric_samples, [:sampled_at])
  end
end
