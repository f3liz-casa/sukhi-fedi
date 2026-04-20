# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.DbNatsListener do
  @moduledoc """
  NATS listener for the legacy `db.>` request/reply subjects (used by
  Deno's HTTP API layer to read/write the Postgres system of record).

  This module is a thin dispatcher: it subscribes to the wildcard and
  delegates to topic-prefixed handlers in `SukhiFedi.Nats.*`. The
  handlers live in bounded-context modules (Accounts, Notes, Content,
  Admin) so each one stays small and testable.

  The whole `db.*` surface is scheduled to disappear in stage 3-b once
  Deno loses its HTTP server; at that point the handler modules
  continue to exist as plain Elixir context modules called directly
  from controllers.
  """

  use GenServer
  require Logger

  alias SukhiFedi.Nats.{Accounts, Admin, Content, Helpers, Notes}

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    # db.> is a multi-level wildcard; catches topics like db.admin.report.list.
    {:ok, _sub} = Gnat.sub(:gnat, self(), "db.>")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:msg, %{topic: topic, reply_to: reply_to, body: body}}, state) do
    Task.start(fn ->
      case Jason.decode(body) do
        {:ok, %{"request_id" => _req_id, "payload" => payload}} ->
          result = dispatch(topic, payload)
          Gnat.pub(:gnat, reply_to, Jason.encode!(result))

        _ ->
          :ok
      end
    end)

    {:noreply, state}
  end

  defp dispatch(topic, payload) do
    result =
      cond do
        prefix?(topic, ["db.account.", "db.auth.", "db.social."]) ->
          Accounts.handle(topic, payload)

        prefix?(topic, ["db.note.", "db.bookmark.", "db.dm."]) ->
          Notes.handle(topic, payload)

        prefix?(topic, ["db.article.", "db.media.", "db.emoji.", "db.feed."]) ->
          Content.handle(topic, payload)

        prefix?(topic, ["db.moderation.", "db.admin."]) ->
          Admin.handle(topic, payload)

        true ->
          :unhandled
      end

    case result do
      :unhandled ->
        Logger.warning("Unhandled NATS db topic: #{topic}")
        Helpers.error_resp("Unknown topic")

      other ->
        other
    end
  end

  defp prefix?(topic, prefixes), do: Enum.any?(prefixes, &String.starts_with?(topic, &1))
end
