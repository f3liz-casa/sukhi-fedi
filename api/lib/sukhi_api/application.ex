# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    routes = SukhiApi.Registry.routes()

    Logger.info("SukhiApi node=#{node()} started with #{length(routes)} route(s):")

    Enum.each(routes, fn route ->
      {m, p, opts} =
        case route do
          {m, p, _h} -> {m, p, []}
          {m, p, _h, opts} -> {m, p, opts}
        end

      scope_tag =
        case Keyword.get(opts, :scope) do
          nil -> ""
          s -> " (scope: #{s})"
        end

      Logger.info("  #{m |> Atom.to_string() |> String.upcase()} #{p}#{scope_tag}")
    end)

    # No children required right now — the plugin is driven entirely by
    # inbound :rpc.call from the gateway. Supervisors go here when a
    # capability grows background state.
    Supervisor.start_link([], strategy: :one_for_one, name: SukhiApi.Supervisor)
  end
end
