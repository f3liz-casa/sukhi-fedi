# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Stats do
  @moduledoc """
  Aggregate metrics for the admin dashboard.

  A single `dashboard/0` call rolls up accounts, statuses, federation
  known/blocked domains, and moderation queue counts. The result is
  cached in ETS for 30 seconds — admin dashboards poll often but the
  numbers don't need to be second-fresh.
  """

  import Ecto.Query

  alias SukhiFedi.Repo

  alias SukhiFedi.Schema.{
    Account,
    Follow,
    InstanceBlock,
    Note,
    OauthAccessToken,
    Report
  }

  @cache_table :sukhi_fedi_stats_cache
  @cache_key :dashboard
  @cache_ttl_ms 30_000

  @doc """
  Return a dashboard-shaped map. Hits ETS if the last call was within
  30 seconds; otherwise runs the aggregate queries and refreshes the
  cache.
  """
  @spec dashboard() :: map()
  def dashboard do
    case cache_get() do
      {:ok, value} -> value
      :miss -> cache_put(compute())
    end
  end

  defp compute do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    minus_1d = DateTime.add(now, -1 * 86_400, :second)
    minus_7d = DateTime.add(now, -7 * 86_400, :second)
    minus_30d = DateTime.add(now, -30 * 86_400, :second)

    accounts_total = Repo.aggregate(Account, :count, :id)

    accounts_suspended =
      Repo.aggregate(from(a in Account, where: not is_nil(a.suspended_at)), :count, :id)

    accounts_admins =
      Repo.aggregate(from(a in Account, where: a.is_admin == true), :count, :id)

    active_7d = count_active_since(minus_7d)
    active_30d = count_active_since(minus_30d)

    statuses_total = Repo.aggregate(Note, :count, :id)

    statuses_last_24h =
      Repo.aggregate(from(n in Note, where: n.created_at > ^minus_1d), :count, :id)

    statuses_last_7d =
      Repo.aggregate(from(n in Note, where: n.created_at > ^minus_7d), :count, :id)

    known_domains = count_known_domains()

    blocked_domains = Repo.aggregate(InstanceBlock, :count, :id)

    open_reports =
      Repo.aggregate(from(r in Report, where: r.status == "open"), :count, :id)

    resolved_reports_7d =
      Repo.aggregate(
        from(r in Report,
          where: r.status == "resolved" and not is_nil(r.resolved_at) and r.resolved_at > ^minus_7d
        ),
        :count,
        :id
      )

    %{
      accounts: %{
        total: accounts_total,
        local: accounts_total,
        remote: 0,
        suspended: accounts_suspended,
        admins: accounts_admins,
        active_last_7d: active_7d,
        active_last_30d: active_30d
      },
      statuses: %{
        total: statuses_total,
        local: statuses_total,
        last_24h: statuses_last_24h,
        last_7d: statuses_last_7d
      },
      federation: %{
        known_domains: known_domains,
        blocked_domains: blocked_domains
      },
      moderation: %{
        open_reports: open_reports,
        resolved_reports_7d: resolved_reports_7d
      },
      generated_at: DateTime.to_iso8601(now)
    }
  end

  defp count_active_since(%DateTime{} = since) do
    # Distinct accounts that touched an access token recently (the OAuth
    # layer refreshes `last_used_at` on every `verify_bearer`).
    query =
      from t in OauthAccessToken,
        where: not is_nil(t.account_id) and not is_nil(t.last_used_at) and t.last_used_at > ^since,
        distinct: t.account_id,
        select: t.account_id

    Repo.aggregate(subquery(query), :count, :account_id)
  end

  defp count_known_domains do
    # Each follower is stored by its ActivityPub actor URI. The set of
    # remote domains we know about is the set of distinct hosts across
    # those URIs (plus local, minus nil parses).
    query =
      from f in Follow,
        where: not is_nil(f.follower_uri),
        select: f.follower_uri,
        distinct: true

    query
    |> Repo.all()
    |> Enum.map(&host_of/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> length()
  end

  defp host_of(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{host: h} when is_binary(h) and h != "" -> h
      _ -> nil
    end
  end

  defp host_of(_), do: nil

  # ── cache ────────────────────────────────────────────────────────────────

  defp cache_get do
    ensure_table()

    case :ets.lookup(@cache_table, @cache_key) do
      [{_, value, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at,
          do: {:ok, value},
          else: :miss

      [] ->
        :miss
    end
  end

  defp cache_put(value) do
    ensure_table()
    expires_at = System.monotonic_time(:millisecond) + @cache_ttl_ms
    :ets.insert(@cache_table, {@cache_key, value, expires_at})
    value
  end

  defp ensure_table do
    case :ets.whereis(@cache_table) do
      :undefined ->
        :ets.new(@cache_table, [:set, :public, :named_table, read_concurrency: true])

      _ref ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end
end
