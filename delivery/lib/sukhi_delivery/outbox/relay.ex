# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Outbox.Relay do
  @moduledoc """
  Consumes pending rows from the shared `outbox` table (written by the
  gateway via `SukhiFedi.Outbox.enqueue_multi/6`) and publishes them to
  NATS JetStream. "DB commit = NATS durable" semantics.

  Wakeups:
    * Postgres `NOTIFY outbox_new` (fired by the AFTER INSERT trigger
      installed by the gateway's outbox migration)
    * Periodic fallback tick

  Uses `FOR UPDATE SKIP LOCKED` so multiple relay instances cooperate
  safely — each claims a disjoint batch.
  """

  use GenServer
  require Logger
  import Ecto.Query

  alias SukhiDelivery.Repo
  alias SukhiDelivery.Schema.OutboxEvent

  @poll_interval_ms 30_000
  @batch_size 100
  @max_attempts 10

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, notifier} = Postgrex.Notifications.start_link(postgrex_config())
    {:ok, _ref} = Postgrex.Notifications.listen(notifier, "outbox_new")

    # Catch rows that were inserted before this process came up.
    send(self(), :tick)

    {:ok, %{notifier: notifier}}
  end

  @impl true
  def handle_info({:notification, _pid, _ref, "outbox_new", _payload}, state) do
    publish_pending()
    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    publish_pending()
    Process.send_after(self(), :tick, @poll_interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("SukhiDelivery.Outbox.Relay ignoring: #{inspect(msg)}")
    {:noreply, state}
  end

  defp publish_pending do
    Repo.transaction(fn ->
      events =
        from(e in OutboxEvent,
          where: e.status == "pending" and e.attempts < @max_attempts,
          order_by: [asc: e.id],
          limit: @batch_size,
          lock: "FOR UPDATE SKIP LOCKED"
        )
        |> Repo.all()

      {published_ids, poison} =
        events
        |> Stream.map(&{&1, do_publish(&1)})
        |> tally()

      deferred = length(events) - length(published_ids) - length(poison)

      if deferred > 0 do
        Logger.warning(
          "Outbox.Relay: NATS unreachable, deferred #{deferred} pending event(s) " <>
            "— attempts untouched, will retry on reconnect"
        )
      end

      apply_results(published_ids, poison)
    end)
  rescue
    e ->
      Logger.error("Outbox.Relay batch failed: #{Exception.message(e)}")
      :error
  end

  @doc """
  Fold per-event publish outcomes into `{published_ids, poison}`.

  Stops at the first `:disconnected` outcome — NATS being unreachable is the
  connection's fault, not the event's, so that row and every one after it
  stay `pending` with `attempts` untouched. Only `:poison` (a row we can
  never encode) is collected to count against `attempts`. Driven over a
  `Stream`, the `:halt` also stops further publish attempts mid-batch.
  """
  @spec tally(Enumerable.t()) :: {list(), list()}
  def tally(outcomes) do
    Enum.reduce_while(outcomes, {[], []}, fn
      {event, :ok}, {ok_ids, poison} ->
        {:cont, {[event.id | ok_ids], poison}}

      {event, {:poison, reason}}, {ok_ids, poison} ->
        {:cont, {ok_ids, [{event, reason} | poison]}}

      {_event, {:disconnected, _reason}}, acc ->
        {:halt, acc}
    end)
  end

  defp apply_results([], []), do: :ok

  defp apply_results(published_ids, poison) do
    now = DateTime.utc_now()

    unless published_ids == [] do
      from(e in OutboxEvent, where: e.id in ^published_ids)
      |> Repo.update_all(set: [status: "published", published_at: now])
    end

    Enum.each(poison, fn {event, reason} ->
      new_attempts = event.attempts + 1
      new_status = if new_attempts >= @max_attempts, do: "failed", else: "pending"

      event
      |> Ecto.Changeset.change(%{
        attempts: new_attempts,
        last_error: inspect(reason),
        status: new_status
      })
      |> Repo.update!()

      Logger.warning(
        "Outbox.Relay could not encode event (attempt #{new_attempts}) " <>
          "id=#{event.id} subject=#{event.subject}: #{inspect(reason)}"
      )
    end)

    :ok
  end

  # Classify one event's publish attempt:
  #   :ok                 — handed to NATS.
  #   {:poison, reason}   — payload can't be encoded; this row will never
  #                         succeed, so it counts against `attempts`.
  #   {:disconnected, _}  — NATS unreachable; the event is fine. The caller
  #                         defers it without touching `attempts`, so an
  #                         outage can't burn the poison-retry budget.
  defp do_publish(event) do
    case encode_body(event.payload) do
      {:ok, body} -> publish(event.id, event.subject, body)
      {:error, reason} -> {:poison, reason}
    end
  end

  defp encode_body(payload) do
    {:ok, JSON.encode!(payload)}
  rescue
    e -> {:error, {:encode, Exception.message(e)}}
  end

  defp publish(id, subject, body) do
    headers = [{"Nats-Msg-Id", "outbox-#{id}"}]

    case Gnat.pub(:gnat_delivery, subject, body, headers: headers) do
      :ok -> :ok
      other -> {:disconnected, other}
    end
  rescue
    e -> {:disconnected, Exception.message(e)}
  end

  defp postgrex_config do
    Repo.config()
    |> Keyword.take([
      :hostname,
      :port,
      :username,
      :password,
      :database,
      :ssl,
      :ssl_opts
    ])
  end
end
