# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SukhiDelivery.PromEx,
      SukhiDelivery.Repo,
      {Gnat.ConnectionSupervisor, nats_connection_settings()},
      # Outbound HTTP pool for remote inbox POSTs. Tune via
      # `sukhi_delivery_pool_utilization` (stays near 1.0 → scale up).
      {Finch,
       name: SukhiDelivery.Finch,
       pools: %{
         default: [size: 50, count: 4]
       }},
      {Oban, Application.fetch_env!(:sukhi_delivery, Oban)},
      # Transactional Outbox relay: publishes `outbox` rows (written by
      # the gateway) to NATS JetStream.
      SukhiDelivery.Outbox.Relay,
      # JetStream subscriber that turns published outbox events into
      # Oban delivery jobs (FedifyClient.translate → Worker fan-out).
      SukhiDelivery.Outbox.Consumer
    ]

    opts = [strategy: :one_for_one, name: SukhiDelivery.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp nats_connection_settings do
    nats_cfg = Application.get_env(:sukhi_delivery, :nats, [])
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
