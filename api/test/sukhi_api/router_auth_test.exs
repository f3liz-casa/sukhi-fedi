# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.RouterAuthTest do
  @moduledoc """
  Tests the auth plug behavior in `SukhiApi.Router` against real
  capability routes shipped in lib/. The Registry only discovers
  lib/ modules, so we exercise:

    * `GET  /api/v1/instance` — 3-tuple, unauthenticated
    * `POST /api/v1/apps`     — 3-tuple, unauthenticated
    * `POST /api/v1/apps/verify_credentials` — scope: "read"
    * `GET  /api/v1/accounts/verify_credentials` — scope: "read:accounts"
  """

  use ExUnit.Case, async: false

  alias SukhiApi.Router

  defmodule FakeRpc do
    # Plays back canned `verify_bearer/1` responses keyed by token.
    # Tests `Application.put_env(:sukhi_api, :fake_rpc, %{token => response})`
    # before calling Router.handle/1.
    def call(mod, fun, args), do: call(mod, fun, args, 5_000)

    def call(SukhiFedi.OAuth, :verify_bearer, [token], _timeout) do
      table = Application.get_env(:sukhi_api, :fake_rpc, %{})

      case Map.get(table, token, :not_configured) do
        :not_configured -> {:error, :not_connected}
        canned -> {:ok, canned}
      end
    end

    def call(_, _, _, _), do: {:error, :not_connected}
  end

  setup do
    prev_rpc = Application.get_env(:sukhi_api, :gateway_rpc_impl)
    prev_addons = Application.get_env(:sukhi_api, :enabled_addons)
    prev_table = Application.get_env(:sukhi_api, :fake_rpc)

    Application.put_env(:sukhi_api, :gateway_rpc_impl, FakeRpc)
    Application.put_env(:sukhi_api, :enabled_addons, :all)
    Application.put_env(:sukhi_api, :fake_rpc, %{})

    on_exit(fn ->
      restore(:gateway_rpc_impl, prev_rpc)
      restore(:enabled_addons, prev_addons)
      restore(:fake_rpc, prev_table)
    end)

    :ok
  end

  test "3-tuple route returns 200 without a token (GET /api/v1/instance)" do
    {:ok, resp} =
      Router.handle(%{
        method: "GET",
        path: "/api/v1/instance",
        headers: []
      })

    assert resp.status == 200
  end

  test "scoped route without Authorization header returns 401" do
    {:ok, resp} =
      Router.handle(%{
        method: "GET",
        path: "/api/v1/accounts/verify_credentials",
        headers: []
      })

    assert resp.status == 401
    assert Jason.decode!(resp.body)["error"] == "invalid_token"
  end

  test "valid token with sufficient scope (read:accounts) returns 200" do
    Application.put_env(:sukhi_api, :fake_rpc, %{
      "good" =>
        {:ok,
         %{
           account: %{
             id: 42,
             username: "alice",
             display_name: "Alice",
             summary: "hi",
             is_bot: false,
             avatar_url: nil,
             banner_url: nil,
             created_at: ~U[2026-01-01 00:00:00Z]
           },
           app: %{id: 7, name: "smoke"},
           scopes: ["read:accounts", "write"]
         }}
    })

    {:ok, resp} =
      Router.handle(%{
        method: "GET",
        path: "/api/v1/accounts/verify_credentials",
        headers: [{"authorization", "Bearer good"}]
      })

    assert resp.status == 200
    body = Jason.decode!(resp.body)
    assert body["id"] == "42"
    assert body["username"] == "alice"
  end

  test "scope superset (granted=[read:accounts, write], required=read:accounts) → 200" do
    Application.put_env(:sukhi_api, :fake_rpc, %{
      "scoped" =>
        {:ok,
         %{
           account: %{
             id: 1,
             username: "x",
             display_name: "X",
             summary: "",
             is_bot: false,
             avatar_url: nil,
             banner_url: nil,
             created_at: ~U[2026-01-01 00:00:00Z]
           },
           app: %{id: 1, name: "a"},
           scopes: ["read:accounts", "write"]
         }}
    })

    {:ok, resp} =
      Router.handle(%{
        method: "GET",
        path: "/api/v1/accounts/verify_credentials",
        headers: [{"authorization", "Bearer scoped"}]
      })

    assert resp.status == 200
  end

  test "scope mismatch (required=read:accounts, granted=read) → 403" do
    Application.put_env(:sukhi_api, :fake_rpc, %{
      "narrow" =>
        {:ok,
         %{
           account: %{id: 1, username: "x"},
           app: %{id: 1, name: "a"},
           scopes: ["read"]
         }}
    })

    {:ok, resp} =
      Router.handle(%{
        method: "GET",
        path: "/api/v1/accounts/verify_credentials",
        headers: [{"authorization", "Bearer narrow"}]
      })

    assert resp.status == 403
    body = Jason.decode!(resp.body)
    assert body["error"] == "insufficient_scope"
    assert body["scope"] == "read:accounts"
  end

  test "verify_bearer returned :invalid_token → 401" do
    Application.put_env(:sukhi_api, :fake_rpc, %{
      "bad" => {:error, :invalid_token}
    })

    {:ok, resp} =
      Router.handle(%{
        method: "GET",
        path: "/api/v1/accounts/verify_credentials",
        headers: [{"authorization", "Bearer bad"}]
      })

    assert resp.status == 401
  end

  test "gateway not connected → 503" do
    {:ok, resp} =
      Router.handle(%{
        method: "GET",
        path: "/api/v1/accounts/verify_credentials",
        headers: [{"authorization", "Bearer anything"}]
      })

    assert resp.status == 503
    assert Jason.decode!(resp.body)["error"] == "gateway_not_connected"
  end

  test "missing Bearer scheme → 401" do
    {:ok, resp} =
      Router.handle(%{
        method: "GET",
        path: "/api/v1/accounts/verify_credentials",
        headers: [{"authorization", "Basic foo"}]
      })

    assert resp.status == 401
  end

  defp restore(key, nil), do: Application.delete_env(:sukhi_api, key)
  defp restore(key, value), do: Application.put_env(:sukhi_api, key, value)
end
