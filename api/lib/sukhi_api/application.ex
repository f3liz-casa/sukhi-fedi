# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    routes = SukhiApi.Registry.routes()

    Logger.info("SukhiApi node=#{node()} started with #{length(routes)} route(s):")

    Enum.each(routes, fn {m, p, _h} ->
      Logger.info("  #{m |> Atom.to_string() |> String.upcase()} #{p}")
    end)

    # No children required right now — the plugin is driven entirely by
    # inbound :rpc.call from the gateway. Supervisors go here when a
    # capability grows background state.
    Supervisor.start_link([], strategy: :one_for_one, name: SukhiApi.Supervisor)
  end
end
