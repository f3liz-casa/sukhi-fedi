# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SukhiFedi.Repo,
      {Bandit, plug: SukhiFedi.Web.Router, port: 4000},
      {Gnat.ConnectionSupervisor, nats_connection_settings()},
      SukhiFedi.Cache.Ets,
      {Oban, Application.fetch_env!(:sukhi_fedi, Oban)}
    ]

    opts = [strategy: :one_for_one, name: SukhiFedi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp nats_connection_settings do
    %{
      name: :gnat,
      connection_settings: [
        %{host: "127.0.0.1", port: 4222}
      ]
    }
  end
end
