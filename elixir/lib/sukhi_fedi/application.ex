# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    OpentelemetryEcto.setup([:sukhi_fedi, :repo])
    OpentelemetryOban.setup()

    children = [
      SukhiFedi.PromEx,
      SukhiFedi.Repo,
      {Bandit, plug: SukhiFedi.Web.Router, port: 4000},
      {Gnat.ConnectionSupervisor, nats_connection_settings()},
      SukhiFedi.Cache.Ets,
      {Oban, Application.fetch_env!(:sukhi_fedi, Oban)},
      # NATS listener for db.* subjects (Deno HTTP API → Elixir DB)
      SukhiFedi.Web.DbNatsListener,
      # Streaming pub/sub registry (holds subscriber PIDs per stream key)
      SukhiFedi.Streaming.Registry,
      # NATS listener that broadcasts new posts to streaming subscribers
      SukhiFedi.Streaming.NatsListener
    ]

    opts = [strategy: :one_for_one, name: SukhiFedi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp nats_connection_settings do
    nats_cfg = Application.get_env(:sukhi_fedi, :nats, [])
    host = Keyword.get(nats_cfg, :host, "127.0.0.1")
    port = Keyword.get(nats_cfg, :port, 4222)

    %{
      name: :gnat,
      connection_settings: [
        %{host: host, port: port}
      ]
    }
  end
end
