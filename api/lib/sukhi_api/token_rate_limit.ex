# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.TokenRateLimit do
  @moduledoc """
  Per-token rate limiter, fixed-window.

  Mastodon's published authenticated REST limit is 300 requests per 5
  minutes per access token; this matches that by default and is
  trivially adjustable via opts.

  Buckets are keyed by `SHA256(token) :: window_start`. The window
  rolls automatically — a counter that's past its window's expiry is
  treated as zero. A periodic sweep purges expired rows so the table
  doesn't grow without bound.

  Node-local. Per the OAuth gateway-side accounting, that's enough:
  a single-node :sukhi_api is the assumption; horizontal scale would
  benefit from a shared store (Redis), but we shouldn't pay for it
  until we have to.
  """

  use GenServer

  @table :sukhi_api_token_rate
  @default_limit 300
  @default_window_ms 5 * 60_000
  @sweep_interval_ms 60_000

  # ── public API ──────────────────────────────────────────────────────────

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Charge one hit for `token`. Returns `:ok` if under the limit (and
  bumps the counter), `{:error, :rate_limited, retry_after_seconds}`
  otherwise.

  Opts:
    * `:limit`     — default 300
    * `:window_ms` — default 300_000
  """
  @spec hit(String.t(), keyword()) :: :ok | {:error, :rate_limited, non_neg_integer()}
  def hit(token, opts \\ []) when is_binary(token) do
    limit = Keyword.get(opts, :limit, @default_limit)
    window_ms = Keyword.get(opts, :window_ms, @default_window_ms)

    now = System.system_time(:millisecond)
    window_start = div(now, window_ms) * window_ms
    expires_at = window_start + window_ms
    key = {key_for(token), window_start}

    case safe_update_counter(key, expires_at) do
      n when n <= limit ->
        :ok

      _ ->
        retry_after = max(div(expires_at - now, 1_000), 1)
        {:error, :rate_limited, retry_after}
    end
  end

  # ── GenServer (table owner + sweep) ─────────────────────────────────────

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, write_concurrency: true, read_concurrency: true])
    Process.send_after(self(), :sweep, @sweep_interval_ms)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.system_time(:millisecond)
    ms = [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}]
    :ets.select_delete(@table, ms)
    Process.send_after(self(), :sweep, @sweep_interval_ms)
    {:noreply, state}
  end

  # ── internals ───────────────────────────────────────────────────────────

  # We don't want a separate read-then-write race: `:ets.update_counter/4`
  # is atomic. `default` form lets us initialise the row in one shot,
  # storing the expires_at so the sweep can purge cheaply.
  defp safe_update_counter(key, expires_at) do
    :ets.update_counter(@table, key, {2, 1}, {key, 0, expires_at})
  rescue
    ArgumentError -> 1
  end

  defp key_for(token), do: :crypto.hash(:sha256, token)
end
