# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.OAuthAppsTest do
  use ExUnit.Case, async: false

  alias SukhiApi.Router

  defmodule FakeRpc do
    def call(mod, fun, args), do: call(mod, fun, args, 5_000)

    def call(SukhiFedi.OAuth, fun, args, _timeout) do
      table = Application.get_env(:sukhi_api, :fake_oauth, %{})

      case Map.get(table, {fun, args}, :not_configured) do
        :not_configured ->
          case Map.get(table, fun, :not_configured) do
            :not_configured -> {:error, :not_connected}
            canned -> {:ok, canned}
          end

        canned ->
          {:ok, canned}
      end
    end
  end

  setup do
    prev_rpc = Application.get_env(:sukhi_api, :gateway_rpc_impl)
    prev_addons = Application.get_env(:sukhi_api, :enabled_addons)
    prev_table = Application.get_env(:sukhi_api, :fake_oauth)

    Application.put_env(:sukhi_api, :gateway_rpc_impl, FakeRpc)
    Application.put_env(:sukhi_api, :enabled_addons, :all)
    Application.put_env(:sukhi_api, :fake_oauth, %{})

    on_exit(fn ->
      restore(:gateway_rpc_impl, prev_rpc)
      restore(:enabled_addons, prev_addons)
      restore(:fake_oauth, prev_table)
    end)

    :ok
  end

  test "POST /api/v1/apps returns id, client_id, client_secret on success" do
    Application.put_env(:sukhi_api, :fake_oauth, %{
      register_app:
        {:ok,
         %{
           app: %{
             id: 7,
             name: "smoke",
             client_id: "cid_xyz",
             redirect_uri: "urn:ietf:wg:oauth:2.0:oob",
             website: nil
           },
           client_secret: "sec_abc"
         }}
    })

    {:ok, resp} =
      Router.handle(%{
        method: "POST",
        path: "/api/v1/apps",
        headers: [{"content-type", "application/json"}],
        body:
          Jason.encode!(%{
            "client_name" => "smoke",
            "redirect_uris" => "urn:ietf:wg:oauth:2.0:oob",
            "scopes" => "read"
          })
      })

    assert resp.status == 200

    body = Jason.decode!(resp.body)
    assert body["id"] == "7"
    assert body["name"] == "smoke"
    assert body["client_id"] == "cid_xyz"
    assert body["client_secret"] == "sec_abc"
    assert body["vapid_key"] == nil
  end

  test "POST /api/v1/apps with validation error → 422" do
    Application.put_env(:sukhi_api, :fake_oauth, %{
      register_app: {:error, {:validation, %{name: ["can't be blank"]}}}
    })

    {:ok, resp} =
      Router.handle(%{
        method: "POST",
        path: "/api/v1/apps",
        headers: [{"content-type", "application/json"}],
        body: Jason.encode!(%{})
      })

    assert resp.status == 422
    assert Jason.decode!(resp.body)["error"] == "validation_failed"
  end

  test "POST /api/v1/apps with bad JSON → 400" do
    {:ok, resp} =
      Router.handle(%{
        method: "POST",
        path: "/api/v1/apps",
        headers: [{"content-type", "application/json"}],
        body: "{not json"
      })

    assert resp.status == 400
    assert Jason.decode!(resp.body)["error"] == "invalid_json"
  end

  test "POST /api/v1/apps with gateway down → 503" do
    Application.put_env(:sukhi_api, :fake_oauth, %{})

    {:ok, resp} =
      Router.handle(%{
        method: "POST",
        path: "/api/v1/apps",
        headers: [{"content-type", "application/json"}],
        body: Jason.encode!(%{"client_name" => "x", "redirect_uris" => "y"})
      })

    assert resp.status == 503
  end

  defp restore(key, nil), do: Application.delete_env(:sukhi_api, key)
  defp restore(key, value), do: Application.put_env(:sukhi_api, key, value)
end
