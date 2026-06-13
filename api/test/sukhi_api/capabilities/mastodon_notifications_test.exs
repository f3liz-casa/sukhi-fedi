# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MastodonNotificationsTest do
  use ExUnit.Case, async: false

  alias SukhiApi.Router

  # 戻り値より引数が主役の RPC fake。`types[]=a&types[]=b` が両方
  # ゲートウェイまで届くか(後の一個に潰れないか)を見たいので、
  # Notifications への呼び出しはそのままテストプロセスへ送り返す。
  defmodule CaptureRpc do
    def call(mod, fun, args), do: call(mod, fun, args, 5_000)

    def call(SukhiFedi.OAuth, fun, _args, _t) do
      case Application.get_env(:sukhi_api, :fake_oauth, %{})[fun] do
        nil -> {:error, :not_connected}
        v -> {:ok, v}
      end
    end

    def call(SukhiFedi.Notifications, fun, args, _t) do
      send(Application.get_env(:sukhi_api, :capture_to), {:rpc, fun, args})
      {:ok, []}
    end

    def call(_, _, _, _), do: {:error, :not_connected}
  end

  setup do
    prev = %{
      rpc: Application.get_env(:sukhi_api, :gateway_rpc_impl),
      addons: Application.get_env(:sukhi_api, :enabled_addons),
      oauth: Application.get_env(:sukhi_api, :fake_oauth),
      capture: Application.get_env(:sukhi_api, :capture_to)
    }

    Application.put_env(:sukhi_api, :gateway_rpc_impl, CaptureRpc)
    Application.put_env(:sukhi_api, :enabled_addons, :all)
    Application.put_env(:sukhi_api, :capture_to, self())

    Application.put_env(:sukhi_api, :fake_oauth, %{
      verify_bearer:
        {:ok,
         %{
           account: %{id: 1, username: "alice", display_name: "A", summary: "", is_bot: false},
           app: %{id: 1, name: "x"},
           scopes: ["read:notifications"]
         }}
    })

    on_exit(fn ->
      restore(:gateway_rpc_impl, prev.rpc)
      restore(:enabled_addons, prev.addons)
      restore(:fake_oauth, prev.oauth)
      restore(:capture_to, prev.capture)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:sukhi_api, key)
  defp restore(key, v), do: Application.put_env(:sukhi_api, key, v)

  defp authed_get(path, query) do
    %{
      method: "GET",
      path: path,
      query: query,
      headers: [{"authorization", "Bearer t"}]
    }
  end

  describe "GET /api/v1/notifications filters" do
    test "repeated types[] all reach the gateway" do
      {:ok, resp} =
        Router.handle(
          authed_get("/api/v1/notifications", "types[]=mention&types[]=follow_request")
        )

      assert resp.status == 200
      assert_receive {:rpc, :list, [1, opts]}
      assert opts[:types] == ["mention", "follow_request"]
    end

    test "repeated exclude_types[] all reach the gateway" do
      {:ok, resp} =
        Router.handle(
          authed_get(
            "/api/v1/notifications",
            "exclude_types[]=mention&exclude_types[]=follow_request"
          )
        )

      assert resp.status == 200
      assert_receive {:rpc, :list, [1, opts]}
      assert opts[:exclude_types] == ["mention", "follow_request"]
    end

    test "a single bare value still arrives as a one-element list" do
      {:ok, resp} = Router.handle(authed_get("/api/v1/notifications", "types=mention"))

      assert resp.status == 200
      assert_receive {:rpc, :list, [1, opts]}
      assert opts[:types] == ["mention"]
    end

    test "no filters → no :types / :exclude_types keys" do
      {:ok, resp} = Router.handle(authed_get("/api/v1/notifications", "limit=5"))

      assert resp.status == 200
      assert_receive {:rpc, :list, [1, opts]}
      refute Keyword.has_key?(opts, :types)
      refute Keyword.has_key?(opts, :exclude_types)
    end
  end
end
