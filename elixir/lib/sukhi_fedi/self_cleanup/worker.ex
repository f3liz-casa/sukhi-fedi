# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.SelfCleanup.Worker do
  @moduledoc """
  Hard-deletes one batch of an account's old notes for self-cleanup.

  `SelfCleanup.run(account_id, :execute, opts)` enqueues one job per batch.
  Each job reads the live batch (`SelfCleanup.next_batch/2`) and deletes each
  note through `Notes.Create.delete_note_for_cleanup/3` — the hard-delete +
  ledger + federated `Delete(Note)` in one transaction. Reading the live scope
  (not a frozen id list) means a retried or re-ordered job converges: notes
  deleted by an earlier job, or pinned since, simply aren't in the batch.

  Small-box budget: a job holds at most one batch of ids in memory, and the
  deletion per note is its own short transaction.
  """

  use Oban.Worker, queue: :publish, max_attempts: 3

  require Logger

  alias SukhiFedi.Notes.Create
  alias SukhiFedi.{Repo, SelfCleanup}
  alias SukhiFedi.Schema.Note

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"account_id" => account_id, "older_than_days" => older_than_days} = args
      }) do
    reason = args["reason"]
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    deleted =
      account_id
      |> SelfCleanup.next_batch(older_than_days)
      |> Enum.reduce(0, fn id, count ->
        case Repo.get(Note, id) do
          %Note{} = note ->
            case Create.delete_note_for_cleanup(note, now, reason) do
              {:ok, _} -> count + 1
              # transient write failure — Oban retries the whole job;
              # the live scope re-reads and the ledger exclusion skips done notes.
              _ -> count
            end

          nil ->
            # note already gone (deleted by another path); skip
            count
        end
      end)

    Logger.info("self_cleanup worker: account=#{account_id}, deleted=#{deleted}")
    :ok
  end
end
