# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Maintenance.ArchiveIntegrity do
  @moduledoc """
  Daily read-only health check over the inbound/outbound archives. A
  file-level backup can't tell that the archive *itself* quietly stopped
  writing to S3 — this can: it counts the index rows and HEAD-checks that the
  most recent inbound original is actually present in the bucket. A missing
  object or an unreachable bucket logs a WARNING; everything else logs an INFO
  summary.

  Runs on the gateway via the existing Oban Cron plugin (it owns the Repo and
  the rustfs credentials). Also callable by hand:

      bin/sukhi_fedi rpc 'SukhiFedi.Maintenance.ArchiveIntegrity.run()'

  This watches the live archive, not the off-host backup — it's safe to run
  whether or not the backup timers are installed.
  """

  use Oban.Worker, queue: :monitor, max_attempts: 1

  import Ecto.Query
  require Logger

  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{InboundEvent, OutboundEvent}

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: run()

  @spec run() :: map()
  def run do
    last_in = Repo.one(from(e in InboundEvent, order_by: [desc: e.received_at], limit: 1))

    summary = %{
      inbound_events: Repo.aggregate(InboundEvent, :count, :id),
      outbound_events: Repo.aggregate(OutboundEvent, :count, :id),
      last_inbound_at: last_in && last_in.received_at,
      latest_object: check_latest_object(last_in)
    }

    case summary.latest_object do
      :missing ->
        Logger.warning("archive_integrity: latest inbound object MISSING in S3 — #{inspect(summary)}")

      :error ->
        Logger.warning("archive_integrity: S3 enabled but unreachable — #{inspect(summary)}")

      _ ->
        Logger.info("archive_integrity: #{inspect(summary)}")
    end

    summary
  end

  defp check_latest_object(nil), do: :no_events

  defp check_latest_object(%InboundEvent{object_key: key}) do
    if s3_enabled?() do
      case ExAws.S3.head_object(inbound_bucket(), key) |> ExAws.request() do
        {:ok, _} -> :ok
        {:error, {:http_error, 404, _}} -> :missing
        {:error, _} -> :error
      end
    else
      :disabled
    end
  end

  defp s3_enabled?, do: Application.get_env(:sukhi_fedi, :s3, [])[:enabled] == true

  defp inbound_bucket,
    do: Application.get_env(:sukhi_fedi, :s3, [])[:inbound_bucket] || "inbound"
end
