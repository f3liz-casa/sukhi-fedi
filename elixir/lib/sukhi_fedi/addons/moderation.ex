# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addons.Moderation do
  @moduledoc """
  Moderation addon — mutes, blocks, reports, instance blocks, account
  suspension. Pure Ecto context; no supervision children.

  Admin-visible mutations (suspend/unsuspend, resolve_report,
  block/unblock instance, set_admin via `SukhiFedi.Accounts`) emit
  `sns.outbox.admin.*` events via the transactional outbox. That event
  stream doubles as the audit trail until a queryable `admin_audits`
  table is introduced.
  """

  use SukhiFedi.Addon, id: :moderation

  import Ecto.Query
  alias Ecto.Multi
  alias SukhiFedi.{Outbox, Repo}
  alias SukhiFedi.Schema.{Mute, Block, Report, InstanceBlock, Account}

  # ── user-level mutes / blocks (no admin outbox) ──────────────────────────

  def mute(account_id, target_id, expires_at \\ nil) do
    %Mute{account_id: account_id, target_id: target_id, expires_at: expires_at}
    |> Repo.insert(on_conflict: :nothing)
  end

  def unmute(account_id, target_id) do
    Repo.delete_all(from m in Mute, where: m.account_id == ^account_id and m.target_id == ^target_id)
  end

  def muted?(account_id, target_id) do
    Repo.exists?(
      from m in Mute,
        where:
          m.account_id == ^account_id and m.target_id == ^target_id and
            (is_nil(m.expires_at) or m.expires_at > ^DateTime.utc_now())
    )
  end

  def block(account_id, target_id) do
    %Block{account_id: account_id, target_id: target_id}
    |> Repo.insert(on_conflict: :nothing)
  end

  def unblock(account_id, target_id) do
    Repo.delete_all(from b in Block, where: b.account_id == ^account_id and b.target_id == ^target_id)
  end

  def blocked?(account_id, target_id) do
    Repo.exists?(from b in Block, where: b.account_id == ^account_id and b.target_id == ^target_id)
  end

  # ── reports ──────────────────────────────────────────────────────────────

  def create_report(attrs) do
    %Report{}
    |> Ecto.Changeset.cast(attrs, [:account_id, :target_id, :note_id, :comment])
    |> Ecto.Changeset.validate_required([:target_id])
    |> Ecto.Changeset.put_change(:status, "open")
    |> Repo.insert()
  end

  @spec get_report(integer() | binary()) ::
          {:ok, Report.t()} | {:error, :not_found}
  def get_report(id) do
    case coerce_id(id) && Repo.get(Report, coerce_id(id)) do
      nil -> {:error, :not_found}
      %Report{} = report -> {:ok, Repo.preload(report, [:account, :target, :note, :resolved_by])}
    end
  end

  @doc """
  List reports filtered by status with offset pagination. Returns
  `{:ok, {reports, total}}`. Reports are preloaded with `account`
  (reporter), `target`, `note`, and `resolved_by`.
  """
  @spec list_reports(String.t(), %{offset: non_neg_integer(), limit: pos_integer()}) ::
          {:ok, {[Report.t()], non_neg_integer()}}
  def list_reports(status, %{offset: offset, limit: limit})
      when is_binary(status) and is_integer(offset) and is_integer(limit) do
    base = from r in Report, where: r.status == ^status

    total = Repo.aggregate(base, :count, :id)

    reports =
      base
      |> order_by([r], desc: r.inserted_at)
      |> offset(^offset)
      |> limit(^limit)
      |> preload([:account, :target, :note, :resolved_by])
      |> Repo.all()

    {:ok, {reports, total}}
  end

  @spec resolve_report(integer() | binary(), integer()) ::
          {:ok, Report.t()} | {:error, :not_found}
  def resolve_report(report_id, resolved_by_id) when is_integer(resolved_by_id) do
    case coerce_id(report_id) && Repo.get(Report, coerce_id(report_id)) do
      nil ->
        {:error, :not_found}

      %Report{} = report ->
        changeset =
          Ecto.Changeset.change(report, %{
            status: "resolved",
            resolved_at: DateTime.utc_now() |> DateTime.truncate(:second),
            resolved_by_id: resolved_by_id
          })

        Multi.new()
        |> Multi.update(:report, changeset)
        |> Outbox.enqueue_multi(
          :outbox_event,
          "sns.outbox.admin.report_resolved",
          "report",
          & &1.report.id,
          fn %{report: r} ->
            %{report_id: r.id, target_id: r.target_id, by_id: resolved_by_id}
          end
        )
        |> Repo.transaction()
        |> case do
          {:ok, %{report: r}} -> {:ok, r}
          {:error, _, reason, _} -> {:error, reason}
        end
    end
  end

  # ── instance blocks ──────────────────────────────────────────────────────

  @spec block_instance(String.t(), String.t(), String.t() | nil, integer()) ::
          {:ok, InstanceBlock.t()} | {:error, term()}
  def block_instance(domain, severity, reason, created_by_id)
      when is_binary(domain) and is_binary(severity) and is_integer(created_by_id) do
    changeset =
      Ecto.Changeset.cast(
        %InstanceBlock{},
        %{
          domain: domain,
          severity: severity,
          reason: reason,
          created_by_id: created_by_id
        },
        [:domain, :severity, :reason, :created_by_id]
      )
      |> Ecto.Changeset.validate_required([:domain, :severity])

    Multi.new()
    |> Multi.insert(:block, changeset, on_conflict: :nothing, conflict_target: :domain)
    |> Outbox.enqueue_multi(
      :outbox_event,
      "sns.outbox.admin.instance_blocked",
      "instance_block",
      & &1.block.id,
      fn %{block: b} ->
        %{domain: b.domain, severity: b.severity, reason: b.reason, by_id: created_by_id}
      end
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{block: b}} -> {:ok, b}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  @spec unblock_instance(String.t(), integer()) ::
          {:ok, %{domain: String.t()}} | {:error, :not_found}
  def unblock_instance(domain, by_id) when is_binary(domain) and is_integer(by_id) do
    case Repo.get_by(InstanceBlock, domain: domain) do
      nil ->
        {:error, :not_found}

      %InstanceBlock{} = block ->
        Multi.new()
        |> Multi.delete(:block, block)
        |> Outbox.enqueue_multi(
          :outbox_event,
          "sns.outbox.admin.instance_unblocked",
          "instance_block",
          & &1.block.id,
          fn %{block: b} -> %{domain: b.domain, by_id: by_id} end
        )
        |> Repo.transaction()
        |> case do
          {:ok, %{block: b}} -> {:ok, %{domain: b.domain}}
          {:error, _, reason, _} -> {:error, reason}
        end
    end
  end

  def instance_blocked?(domain) do
    Repo.exists?(from i in InstanceBlock, where: i.domain == ^domain)
  end

  @doc """
  List federated domain blocks with offset pagination. Returns
  `{:ok, {blocks, total}}`.
  """
  @spec list_instance_blocks(%{offset: non_neg_integer(), limit: pos_integer()}) ::
          {:ok, {[InstanceBlock.t()], non_neg_integer()}}
  def list_instance_blocks(%{offset: offset, limit: limit})
      when is_integer(offset) and is_integer(limit) do
    base = InstanceBlock
    total = Repo.aggregate(base, :count, :id)

    blocks =
      from(i in base, order_by: [desc: i.inserted_at])
      |> offset(^offset)
      |> limit(^limit)
      |> Repo.all()

    {:ok, {blocks, total}}
  end

  # ── account suspension ───────────────────────────────────────────────────

  @spec suspend_account(integer() | binary(), integer(), String.t() | nil) ::
          {:ok, Account.t()} | {:error, :not_found}
  def suspend_account(account_id, suspended_by_id, reason) when is_integer(suspended_by_id) do
    case coerce_id(account_id) && Repo.get(Account, coerce_id(account_id)) do
      nil ->
        {:error, :not_found}

      %Account{} = account ->
        changeset =
          Ecto.Changeset.change(account, %{
            suspended_at: DateTime.utc_now() |> DateTime.truncate(:second),
            suspended_by_id: suspended_by_id,
            suspension_reason: reason
          })

        Multi.new()
        |> Multi.update(:account, changeset)
        |> Outbox.enqueue_multi(
          :outbox_event,
          "sns.outbox.admin.account_suspended",
          "account",
          & &1.account.id,
          fn %{account: a} ->
            %{account_id: a.id, by_id: suspended_by_id, reason: reason}
          end
        )
        |> Repo.transaction()
        |> case do
          {:ok, %{account: a}} -> {:ok, a}
          {:error, _, reason, _} -> {:error, reason}
        end
    end
  end

  @spec unsuspend_account(integer() | binary(), integer()) ::
          {:ok, Account.t()} | {:error, :not_found}
  def unsuspend_account(account_id, by_id) when is_integer(by_id) do
    case coerce_id(account_id) && Repo.get(Account, coerce_id(account_id)) do
      nil ->
        {:error, :not_found}

      %Account{} = account ->
        changeset =
          Ecto.Changeset.change(account, %{
            suspended_at: nil,
            suspended_by_id: nil,
            suspension_reason: nil
          })

        Multi.new()
        |> Multi.update(:account, changeset)
        |> Outbox.enqueue_multi(
          :outbox_event,
          "sns.outbox.admin.account_unsuspended",
          "account",
          & &1.account.id,
          fn %{account: a} -> %{account_id: a.id, by_id: by_id} end
        )
        |> Repo.transaction()
        |> case do
          {:ok, %{account: a}} -> {:ok, a}
          {:error, _, reason, _} -> {:error, reason}
        end
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  defp coerce_id(id) when is_integer(id), do: id

  defp coerce_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp coerce_id(_), do: nil
end
