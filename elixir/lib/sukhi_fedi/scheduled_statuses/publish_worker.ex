# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.ScheduledStatuses.PublishWorker do
  @moduledoc """
  Publishes one scheduled status when its `publish_at` arrives.

  The job carries only the `scheduled_statuses` row id. At `publish_at`
  Oban runs `perform/1`, which replays the stored params through the
  *real* `Notes.create_status/2` — the same `Ecto.Multi` + transactional
  outbox a live POST takes — so the note's validation, federation and
  zero-loss delivery are not duplicated here, only deferred. The row is
  deleted once the note is created (a published schedule has no further
  use; a cancel before publish deletes both the row and this job).

  A `:not_found` row means the schedule was cancelled (its job delete
  raced the trigger) — that is a no-op success, not an error.
  """

  use Oban.Worker, queue: :publish, max_attempts: 3

  require Logger

  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.ScheduledStatus

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"scheduled_status_id" => id}}) do
    case Repo.get(ScheduledStatus, id) do
      nil ->
        :ok

      %ScheduledStatus{account_id: account_id, params: params} = scheduled ->
        publish(scheduled, account_id, params)
    end
  end

  defp publish(scheduled, account_id, params) do
    case SukhiFedi.Notes.create_status(account_id, params) do
      {:ok, _note} ->
        Repo.delete(scheduled)
        :ok

      {:error, reason} = err ->
        # The note's own changeset rejected the stored params (e.g. a
        # media row was deleted between scheduling and publish). Retrying
        # won't fix a permanent validation failure, so log and stop —
        # Oban discards after max_attempts either way.
        Logger.warning(
          "scheduled publish #{scheduled.id} failed: #{inspect(reason)}"
        )

        err
    end
  end
end
