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

      {published_ids, failures} =
        Enum.reduce(events, {[], []}, fn event, {ok_ids, fail_acc} ->
          case do_publish(event) do
            :ok -> {[event.id | ok_ids], fail_acc}
            {:error, reason} -> {ok_ids, [{event, reason} | fail_acc]}
          end
        end)

      apply_results(published_ids, failures)
    end)
  rescue
    e ->
      Logger.error("Outbox.Relay batch failed: #{Exception.message(e)}")
      :error
  end

  defp apply_results([], []), do: :ok

  defp apply_results(published_ids, failures) do
    now = DateTime.utc_now()

    unless published_ids == [] do
      from(e in OutboxEvent, where: e.id in ^published_ids)
      |> Repo.update_all(set: [status: "published", published_at: now])
    end

    Enum.each(failures, fn {event, reason} ->
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
        "Outbox.Relay publish failed (attempt #{new_attempts}) " <>
          "id=#{event.id} subject=#{event.subject}: #{inspect(reason)}"
      )
    end)

    :ok
  end

  defp do_publish(event) do
    body = Jason.encode!(event.payload)
    headers = [{"Nats-Msg-Id", "outbox-#{event.id}"}]

    case Gnat.pub(:gnat, event.subject, body, headers: headers) do
      :ok -> :ok
      {:error, _} = err -> err
      other -> {:error, {:unexpected, other}}
    end
  rescue
    e -> {:error, {:exception, Exception.message(e)}}
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
