# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule SukhiFedi.IntegrationCase do
  @moduledoc """
  Support for integration tests running against a live docker-compose.test.yml
  stack.

  Expected services (see docker-compose.test.yml):
    * Postgres on localhost:15432 (database: sukhi_fedi_test)
    * NATS on localhost:14222 (with OUTBOX and DOMAIN_EVENTS streams)
    * Deno fedify NATS Micro service connected to the above NATS

  Bring up the stack:

      docker compose -f docker-compose.test.yml up -d

  Run integration tests:

      mix test --only integration

  The default `mix test` excludes the `:integration` tag so unit tests stay
  hermetic.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import SukhiFedi.IntegrationCase
    end
  end

  setup do
    bypass = Bypass.open()

    {:ok,
     mock_remote: bypass,
     mock_remote_url: "http://localhost:#{bypass.port}"}
  end

  @doc """
  Build the URL of a mock remote actor's inbox. Useful when writing
  delivery tests.
  """
  def mock_remote_inbox_url(bypass, actor \\ "mockuser") do
    "http://localhost:#{bypass.port}/users/#{actor}/inbox"
  end
end
