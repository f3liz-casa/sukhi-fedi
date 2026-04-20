# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.PluginPlugTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias SukhiFedi.Web.PluginPlug

  describe "call/2 with no nodes" do
    test "returns 503 and halts when node list is empty" do
      conn =
        conn(:get, "/api/v1/instance")
        |> Map.put(:body_params, %{})

      result = PluginPlug.call(conn, PluginPlug.init(nodes: []))

      assert result.status == 503
      assert result.halted
      assert Jason.decode!(result.resp_body) == %{"error" => "plugin_unavailable"}
    end
  end

  describe "call/2 with unreachable nodes" do
    test "returns 503 when all configured nodes refuse to connect" do
      conn =
        conn(:post, "/api/v1/statuses")
        |> Map.put(:body_params, %{"status" => "hello"})

      result =
        PluginPlug.call(
          conn,
          PluginPlug.init(nodes: [:"nonexistent@invalid-host-#{:rand.uniform(999_999)}"])
        )

      assert result.status == 503
      assert result.halted
    end
  end
end
