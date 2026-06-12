# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Mailer.Capture do
  @moduledoc """
  Test transport: mails pile up in a public ETS table instead of going
  out. `all/0` returns them oldest-first; `clear/0` between tests;
  `last_to/1` digs out the most recent mail for one address (handy for
  fishing the 6-digit code back out of the body).
  """

  @behaviour SukhiFedi.Mailer

  @table :sukhi_mailer_capture

  @impl true
  def deliver(_conf, to, subject, body) do
    ensure_table()
    :ets.insert(@table, {System.unique_integer([:monotonic]), %{to: to, subject: subject, body: body}})
    :ok
  end

  def all do
    ensure_table()
    @table |> :ets.tab2list() |> Enum.sort() |> Enum.map(fn {_, mail} -> mail end)
  end

  def clear do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  def last_to(to) do
    all() |> Enum.filter(&(&1.to == to)) |> List.last()
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        # Owned by whichever test process touches it first; `:heir` to no
        # one is fine because the table is re-created on demand.
        :ets.new(@table, [:named_table, :public, :ordered_set])

      _ ->
        @table
    end
  rescue
    # Two async tests racing into :ets.new — one wins, both proceed.
    ArgumentError -> @table
  end
end
