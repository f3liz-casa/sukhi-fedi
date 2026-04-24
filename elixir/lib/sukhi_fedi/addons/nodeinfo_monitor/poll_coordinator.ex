# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addons.NodeinfoMonitor.PollCoordinator do
  @moduledoc """
  Oban cron entry point. Enumerates active `MonitoredInstance`s due
  for polling and enqueues one `PollWorker` job per instance.

  Each `PollWorker` job is marked `unique` for ~50 minutes to avoid
  double-enqueueing the same instance when a poll cycle takes longer
  than the cron tick.
  """

  use Oban.Worker, queue: :monitor, max_attempts: 1

  require Logger

  alias SukhiFedi.Addons.NodeinfoMonitor
  alias SukhiFedi.Addons.NodeinfoMonitor.PollWorker

  # Cron fires every 10 minutes. Give each instance a bit over-window so
  # we never skip a tick if the previous coordinator run ran long.
  @default_max_age_seconds 500
  @unique_period_seconds 500

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    max_age = args["max_age_seconds"] || @default_max_age_seconds
    instances = NodeinfoMonitor.list_active_due(max_age)

    Logger.info("PollCoordinator: enqueuing polls for #{length(instances)} instances")

    Enum.each(instances, fn mi ->
      %{"instance_id" => mi.id}
      |> PollWorker.new(unique: [period: @unique_period_seconds, keys: [:instance_id]])
      |> then(&Oban.insert(SukhiFedi.Oban, &1))
    end)

    :ok
  end
end
