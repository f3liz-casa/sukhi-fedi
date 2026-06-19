# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.NoteDrafts do
  @moduledoc """
  Server-side compose drafts — the cross-device twin of the SPA's local
  `sf.compose_draft`. A draft is the small bag of text the composer
  restores (text, spoiler, sensitive, visibility), kept so the same
  half-written note follows the author to another device.

  Two properties shape this module:

    * **Per-account, always.** Every read and write is scoped by
      `account_id` through the one `owned/1` query, so an author only
      ever sees or touches their own draft. There is exactly one draft
      per account — the unique index makes `upsert/2` a replace.
    * **Never federated.** A draft is private to its author; it carries
      no `ap_id`, never rides the outbox, and is never published from
      here. `delete/1` is therefore a plain row delete — there is no
      federated state to retract (cf. the note-deletion path, which
      *must* federate a `Delete`; a draft has none). The composer prunes
      its draft once the note is actually posted.
  """

  import Ecto.Query

  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Account, NoteDraft}

  @doc "The account's draft, or `nil`."
  @spec get(Account.t() | integer()) :: NoteDraft.t() | nil
  def get(%Account{id: aid}), do: get(aid)
  def get(account_id) when is_integer(account_id), do: owned(account_id)

  @doc """
  Save the account's draft, replacing the one already there (one draft
  per account). `attrs` are the composer's fields with string keys;
  unknown keys are ignored by the changeset. Returns the stored draft or
  `{:error, changeset}` if a field doesn't validate.
  """
  @spec upsert(Account.t() | integer(), map()) ::
          {:ok, NoteDraft.t()} | {:error, Ecto.Changeset.t()}
  def upsert(%Account{id: aid}, attrs), do: upsert(aid, attrs)

  def upsert(account_id, attrs) when is_integer(account_id) do
    (owned(account_id) || %NoteDraft{})
    |> NoteDraft.changeset(Map.put(attrs, "account_id", account_id))
    |> Repo.insert_or_update()
  end

  @doc """
  Discard the account's draft. Idempotent — no draft is still `:ok`. A
  draft is never federated, so this drops the row outright with nothing
  to retract.
  """
  @spec delete(Account.t() | integer()) :: :ok
  def delete(%Account{id: aid}), do: delete(aid)

  def delete(account_id) when is_integer(account_id) do
    case owned(account_id) do
      nil -> :ok
      %NoteDraft{} = draft -> with {:ok, _} <- Repo.delete(draft), do: :ok
    end
  end

  # The single ownership gate: a draft is only ever fetched scoped to the
  # asking account, so no read or write can touch another author's.
  defp owned(account_id) do
    Repo.one(from(d in NoteDraft, where: d.account_id == ^account_id))
  end
end
