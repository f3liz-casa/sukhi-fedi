# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.OAuthTest do
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

    def call(SukhiFedi.Accounts, :get_account_by_session_token, [token], _timeout) do
      table = Application.get_env(:sukhi_api, :fake_sessions, %{})
      {:ok, Map.get(table, token)}
    end
  end

  setup do
    prev_rpc = Application.get_env(:sukhi_api, :gateway_rpc_impl)
    prev_addons = Application.get_env(:sukhi_api, :enabled_addons)
    prev_oauth = Application.get_env(:sukhi_api, :fake_oauth)
    prev_sessions = Application.get_env(:sukhi_api, :fake_sessions)

    Application.put_env(:sukhi_api, :gateway_rpc_impl, FakeRpc)
    Application.put_env(:sukhi_api, :enabled_addons, :all)
    Application.put_env(:sukhi_api, :fake_oauth, %{})
    Application.put_env(:sukhi_api, :fake_sessions, %{})

    on_exit(fn ->
      restore(:gateway_rpc_impl, prev_rpc)
      restore(:enabled_addons, prev_addons)
      restore(:fake_oauth, prev_oauth)
      restore(:fake_sessions, prev_sessions)
    end)

    :ok
  end

  describe "POST /oauth/token" do
    test "authorization_code grant returns token JSON" do
      Application.put_env(:sukhi_api, :fake_oauth, %{
        exchange_code_for_token:
          {:ok,
           %{
             access_token: "at_123",
             refresh_token: "rt_456",
             token_type: "Bearer",
             scope: "read write",
             created_at: 1_700_000_000
           }}
      })

      {:ok, resp} =
        Router.handle(%{
          method: "POST",
          path: "/oauth/token",
          headers: [{"content-type", "application/json"}],
          body:
            Jason.encode!(%{
              "grant_type" => "authorization_code",
              "client_id" => "cid",
              "client_secret" => "sec",
              "code" => "code_xyz",
              "redirect_uri" => "urn:ietf:wg:oauth:2.0:oob"
            })
        })

      assert resp.status == 200
      body = Jason.decode!(resp.body)
      assert body["access_token"] == "at_123"
      assert body["refresh_token"] == "rt_456"
      assert body["token_type"] == "Bearer"
      assert body["scope"] == "read write"
    end

    test "client_credentials grant returns token without refresh_token" do
      Application.put_env(:sukhi_api, :fake_oauth, %{
        client_credentials_grant:
          {:ok,
           %{
             access_token: "at_cc",
             refresh_token: nil,
             token_type: "Bearer",
             scope: "read",
             created_at: 1_700_000_000
           }}
      })

      {:ok, resp} =
        Router.handle(%{
          method: "POST",
          path: "/oauth/token",
          headers: [{"content-type", "application/json"}],
          body:
            Jason.encode!(%{
              "grant_type" => "client_credentials",
              "client_id" => "cid",
              "client_secret" => "sec",
              "scope" => "read"
            })
        })

      assert resp.status == 200
      body = Jason.decode!(resp.body)
      assert body["access_token"] == "at_cc"
      refute Map.has_key?(body, "refresh_token")
    end

    test "invalid_grant returns 400 with error code" do
      Application.put_env(:sukhi_api, :fake_oauth, %{
        exchange_code_for_token: {:error, :invalid_grant}
      })

      {:ok, resp} =
        Router.handle(%{
          method: "POST",
          path: "/oauth/token",
          headers: [{"content-type", "application/json"}],
          body:
            Jason.encode!(%{
              "grant_type" => "authorization_code",
              "client_id" => "cid",
              "client_secret" => "sec",
              "code" => "expired",
              "redirect_uri" => "urn:ietf:wg:oauth:2.0:oob"
            })
        })

      assert resp.status == 400
      assert Jason.decode!(resp.body)["error"] == "invalid_grant"
    end

    test "unsupported grant type → 400 unsupported_grant_type" do
      {:ok, resp} =
        Router.handle(%{
          method: "POST",
          path: "/oauth/token",
          headers: [{"content-type", "application/json"}],
          body: Jason.encode!(%{"grant_type" => "password"})
        })

      assert resp.status == 400
      assert Jason.decode!(resp.body)["error"] == "unsupported_grant_type"
    end

    test "form-encoded body is also accepted" do
      Application.put_env(:sukhi_api, :fake_oauth, %{
        client_credentials_grant:
          {:ok,
           %{
             access_token: "at_form",
             refresh_token: nil,
             token_type: "Bearer",
             scope: "read",
             created_at: 1
           }}
      })

      {:ok, resp} =
        Router.handle(%{
          method: "POST",
          path: "/oauth/token",
          headers: [{"content-type", "application/x-www-form-urlencoded"}],
          body: "grant_type=client_credentials&client_id=cid&client_secret=sec&scope=read"
        })

      assert resp.status == 200
    end
  end

  describe "POST /oauth/revoke" do
    test "always returns 200 on success" do
      Application.put_env(:sukhi_api, :fake_oauth, %{revoke_token: :ok})

      {:ok, resp} =
        Router.handle(%{
          method: "POST",
          path: "/oauth/revoke",
          headers: [{"content-type", "application/json"}],
          body: Jason.encode!(%{"client_id" => "c", "client_secret" => "s", "token" => "t"})
        })

      assert resp.status == 200
    end
  end

  describe "GET /oauth/authorize" do
    test "missing client_id → 400 HTML" do
      {:ok, resp} =
        Router.handle(%{
          method: "GET",
          path: "/oauth/authorize",
          query: "redirect_uri=foo&response_type=code",
          headers: []
        })

      assert resp.status == 400
      assert {"content-type", "text/html; charset=utf-8"} in resp.headers
    end

    test "renders consent form for known client_id" do
      Application.put_env(:sukhi_api, :fake_oauth, %{
        find_app_by_client_id:
          {:ok,
           %{
             id: 1,
             name: "ConsentApp",
             client_id: "cid_in_form",
             redirect_uri: "https://example.com/cb"
           }}
      })

      {:ok, resp} =
        Router.handle(%{
          method: "GET",
          path: "/oauth/authorize",
          query:
            "client_id=cid_in_form&redirect_uri=https://example.com/cb&scope=read&response_type=code&state=xyz",
          headers: []
        })

      assert resp.status == 200
      assert resp.body =~ "ConsentApp"
      assert resp.body =~ "cid_in_form"
      assert resp.body =~ "/oauth/authorize"
    end
  end

  describe "POST /oauth/authorize" do
    test "no session cookie → 401 HTML" do
      {:ok, resp} =
        Router.handle(%{
          method: "POST",
          path: "/oauth/authorize",
          headers: [{"content-type", "application/x-www-form-urlencoded"}],
          body: "client_id=c&redirect_uri=https://example.com/cb&scope=read&state=xyz"
        })

      assert resp.status == 401
    end

    test "valid session redirects with code" do
      Application.put_env(:sukhi_api, :fake_sessions, %{
        "good_session" => %{id: 11, username: "alice"}
      })

      Application.put_env(:sukhi_api, :fake_oauth, %{
        find_app_by_client_id: {:ok, %{id: 1, name: "x", client_id: "c", redirect_uri: "https://example.com/cb"}},
        create_authorization_code: {:ok, %{code: "auth_code_123", state: "xyz"}}
      })

      {:ok, resp} =
        Router.handle(%{
          method: "POST",
          path: "/oauth/authorize",
          headers: [
            {"content-type", "application/x-www-form-urlencoded"},
            {"cookie", "session_token=good_session"}
          ],
          body: "client_id=c&redirect_uri=https%3A%2F%2Fexample.com%2Fcb&scope=read&state=xyz"
        })

      assert resp.status == 302

      location =
        Enum.find_value(resp.headers, fn {k, v} ->
          if String.downcase(k) == "location", do: v
        end)

      assert location =~ "https://example.com/cb"
      assert location =~ "code=auth_code_123"
      assert location =~ "state=xyz"
    end
  end

  defp restore(key, nil), do: Application.delete_env(:sukhi_api, key)
  defp restore(key, value), do: Application.put_env(:sukhi_api, key, value)
end
