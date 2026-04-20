# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Outbox.Relay do
  @moduledoc """
  Consumes pending rows from the `outbox` table and publishes them to
  NATS JetStream. Paired with `SukhiFedi.Outbox.enqueue_multi/6` this
  delivers "DB commit = NATS durable" semantics.

  Wakeups:
    * Postgres `NOTIFY outbox_new` (fired by the AFTER INSERT trigger)
    * Periodic fallback tick

  Uses `FOR UPDATE SKIP LOCKED` so additional relay instances
  (horizontal scale) cooperate safely — each claims a disjoint batch.
  """

  use GenServer
  require Logger
  import Ecto.Query

  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.OutboxEvent

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
    Logger.debug("SukhiFedi.Outbox.Relay ignoring: #{inspect(msg)}")
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

      Enum.each(events, &publish_one/1)
    end)
  rescue
    e ->
      Logger.error("Outbox.Relay batch failed: #{Exception.message(e)}")
      :error
  end

  defp publish_one(event) do
    case do_publish(event) do
      :ok ->
        event
        |> Ecto.Changeset.change(%{
          status: "published",
          published_at: DateTime.utc_now()
        })
        |> Repo.update!()

      {:error, reason} ->
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
    end
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
