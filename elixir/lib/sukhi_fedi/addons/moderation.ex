# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addons.Moderation do
  @moduledoc """
  Moderation addon — mutes, blocks, reports, instance blocks, account
  suspension. Pure Ecto context; no supervision children.
  """

  use SukhiFedi.Addon, id: :moderation

  import Ecto.Query
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Mute, Block, Report, InstanceBlock, Account}

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

  def create_report(attrs) do
    %Report{}
    |> Ecto.Changeset.cast(attrs, [:account_id, :target_id, :note_id, :comment])
    |> Ecto.Changeset.validate_required([:target_id])
    |> Repo.insert()
  end

  def list_reports(status \\ "open") do
    Repo.all(
      from r in Report,
        where: r.status == ^status,
        order_by: [desc: r.inserted_at],
        preload: [:account, :target, :note]
    )
  end

  def resolve_report(report_id, resolved_by_id) do
    Repo.get!(Report, report_id)
    |> Ecto.Changeset.change(%{
      status: "resolved",
      resolved_at: DateTime.utc_now(),
      resolved_by_id: resolved_by_id
    })
    |> Repo.update()
  end

  def block_instance(domain, severity, reason, created_by_id) do
    %InstanceBlock{domain: domain, severity: severity, reason: reason, created_by_id: created_by_id}
    |> Repo.insert(on_conflict: :nothing)
  end

  def unblock_instance(domain) do
    Repo.delete_all(from i in InstanceBlock, where: i.domain == ^domain)
  end

  def instance_blocked?(domain) do
    Repo.exists?(from i in InstanceBlock, where: i.domain == ^domain)
  end

  def list_instance_blocks do
    Repo.all(from i in InstanceBlock, order_by: [desc: i.inserted_at])
  end

  def suspend_account(account_id, suspended_by_id, reason) do
    Repo.get!(Account, account_id)
    |> Ecto.Changeset.change(%{
      suspended_at: DateTime.utc_now(),
      suspended_by_id: suspended_by_id,
      suspension_reason: reason
    })
    |> Repo.update()
  end

  def unsuspend_account(account_id) do
    Repo.get!(Account, account_id)
    |> Ecto.Changeset.change(%{
      suspended_at: nil,
      suspended_by_id: nil,
      suspension_reason: nil
    })
    |> Repo.update()
  end
end
