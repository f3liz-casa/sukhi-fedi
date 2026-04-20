# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addons.NodeinfoMonitor do
  @moduledoc """
  NodeInfo monitor addon — polls registered fediverse domains and posts
  a Note from a bot actor on version changes.

  One monitored domain = one local bot `Account` (`is_bot=true`) plus
  one `MonitoredInstance` row. Polling runs under Oban cron (see
  `elixir/config/config.exs`); version changes flow through the
  standard Outbox → FanOut → Delivery pipeline.
  """

  use SukhiFedi.Addon, id: :nodeinfo_monitor

  import Ecto.Query
  require Logger

  alias SukhiFedi.{Repo, Notes}
  alias SukhiFedi.Schema.{Account, MonitoredInstance, NodeinfoSnapshot}
  alias SukhiFedi.Addons.NodeinfoMonitor.KeyGen

  @doc """
  Register a new domain to monitor. Creates a bot Account and a
  MonitoredInstance atomically in one transaction.
  """
  def register(domain) when is_binary(domain) do
    cleaned = domain |> String.trim() |> String.downcase()

    if valid_domain?(cleaned) do
      keys = KeyGen.generate()
      username = username_for(cleaned)

      account = %Account{
        username: username,
        display_name: cleaned,
        summary: "NodeInfo monitor bot for #{cleaned}",
        public_key_jwk: keys.public_jwk,
        private_key_jwk: keys.private_jwk,
        public_key_pem: keys.public_pem,
        is_bot: true,
        monitored_domain: cleaned
      }

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:account, account)
      |> Ecto.Multi.run(:monitored_instance, fn _, %{account: a} ->
        %MonitoredInstance{}
        |> MonitoredInstance.changeset(%{domain: cleaned, actor_id: a.id})
        |> Repo.insert()
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{monitored_instance: mi}} -> {:ok, mi}
        {:error, _step, reason, _} -> {:error, reason}
      end
    else
      {:error, :invalid_domain}
    end
  end

  def list do
    Repo.all(from(m in MonitoredInstance, order_by: [asc: m.domain]))
  end

  def get(id), do: Repo.get(MonitoredInstance, id)

  def list_active_due(max_age_seconds) do
    threshold = DateTime.add(DateTime.utc_now(), -max_age_seconds, :second)

    from(m in MonitoredInstance,
      where: m.inactive == false,
      where: is_nil(m.last_polled_at) or m.last_polled_at < ^threshold,
      select: m
    )
    |> Repo.all()
  end

  def deactivate(id) do
    case Repo.get(MonitoredInstance, id) do
      nil -> {:error, :not_found}
      mi -> mi |> Ecto.Changeset.change(%{inactive: true}) |> Repo.update()
    end
  end

  def record_snapshot(%MonitoredInstance{} = mi, snapshot) do
    now = DateTime.utc_now()

    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :snapshot,
      NodeinfoSnapshot.changeset(%NodeinfoSnapshot{}, %{
        monitored_instance_id: mi.id,
        polled_at: now,
        version: snapshot[:version],
        software_name: snapshot[:software_name],
        raw: snapshot[:raw]
      })
    )
    |> Ecto.Multi.update(
      :instance,
      Ecto.Changeset.change(mi, %{
        last_polled_at: now,
        last_version: snapshot[:version],
        software_name: snapshot[:software_name],
        consecutive_failures: 0
      })
    )
    |> Repo.transaction()
    |> case do
      {:ok, _} -> {:ok, detect_change(mi.last_version, snapshot[:version])}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  def detect_change(nil, _new), do: :initial
  def detect_change(old, new) when old == new, do: :unchanged
  def detect_change(old, new), do: {:changed, old, new}

  def record_failure(%MonitoredInstance{} = mi, inactive_threshold \\ 168) do
    fails = (mi.consecutive_failures || 0) + 1
    inactive? = fails >= inactive_threshold

    mi
    |> Ecto.Changeset.change(%{consecutive_failures: fails, inactive: inactive?})
    |> Repo.update()
  end

  def publish_change_note(%MonitoredInstance{} = mi, old_version, new_version) do
    content = format_note(mi, old_version, new_version)

    Notes.create_note(%{
      "account_id" => mi.actor_id,
      "content" => content,
      "visibility" => "public"
    })
  end

  defp format_note(mi, old, new) do
    sw = mi.software_name || "unknown"

    "\u{1F514} #{mi.domain} upgraded\n" <>
      "software: #{sw}\n" <>
      "version: #{old || "?"} \u2192 #{new}"
  end

  defp valid_domain?(d) do
    byte_size(d) > 2 and byte_size(d) <= 253 and
      String.match?(d, ~r/^[a-z0-9.-]+\.[a-z]{2,}$/i)
  end

  defp username_for(domain), do: String.replace(domain, ".", "-")
end
