# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MastodonAccountsTest do
  use ExUnit.Case, async: false

  alias SukhiApi.Router

  defmodule FakeRpc do
    def call(mod, fun, args), do: call(mod, fun, args, 5_000)

    def call(SukhiFedi.Accounts, fun, args, _t), do: lookup(:fake_accounts, fun, args)
    def call(SukhiFedi.Social, fun, args, _t), do: lookup(:fake_social, fun, args)
    def call(SukhiFedi.OAuth, fun, args, _t), do: lookup(:fake_oauth, fun, args)
    def call(_, _, _, _), do: {:error, :not_connected}

    defp lookup(env_key, fun, args) do
      table = Application.get_env(:sukhi_api, env_key, %{})

      case Map.get(table, {fun, args}, :not_configured) do
        :not_configured ->
          case Map.get(table, fun, :not_configured) do
            :not_configured -> {:error, :not_connected}
            v -> {:ok, v}
          end

        v ->
          {:ok, v}
      end
    end
  end

  setup do
    prev = %{
      rpc: Application.get_env(:sukhi_api, :gateway_rpc_impl),
      addons: Application.get_env(:sukhi_api, :enabled_addons),
      accounts: Application.get_env(:sukhi_api, :fake_accounts),
      social: Application.get_env(:sukhi_api, :fake_social),
      oauth: Application.get_env(:sukhi_api, :fake_oauth)
    }

    Application.put_env(:sukhi_api, :gateway_rpc_impl, FakeRpc)
    Application.put_env(:sukhi_api, :enabled_addons, :all)
    Application.put_env(:sukhi_api, :fake_accounts, %{})
    Application.put_env(:sukhi_api, :fake_social, %{})

    on_exit(fn ->
      restore(:gateway_rpc_impl, prev.rpc)
      restore(:enabled_addons, prev.addons)
      restore(:fake_accounts, prev.accounts)
      restore(:fake_social, prev.social)
      restore(:fake_oauth, prev.oauth)
    end)

    :ok
  end

  defp account_fixture(id, username) do
    %{
      id: id,
      username: username,
      display_name: String.capitalize(username),
      summary: "hi",
      is_bot: false,
      is_admin: false,
      avatar_url: nil,
      banner_url: nil,
      created_at: ~U[2026-01-01 00:00:00Z]
    }
  end

  defp authed_request(method, path, account, scopes, extra \\ %{}) do
    Application.put_env(:sukhi_api, :fake_oauth, %{
      verify_bearer:
        {:ok,
         %{
           account: account,
           app: %{id: 7, name: "test"},
           scopes: scopes
         }}
    })

    Map.merge(
      %{
        method: method,
        path: path,
        headers: [{"authorization", "Bearer t"}, {"content-type", "application/json"}]
      },
      extra
    )
  end

  describe "GET /api/v1/accounts/verify_credentials" do
    test "returns CredentialAccount for the bound user" do
      account = account_fixture(42, "alice")

      Application.put_env(:sukhi_api, :fake_accounts, %{
        counts_for: %{followers: 3, following: 5, statuses: 12}
      })

      req =
        authed_request(
          "GET",
          "/api/v1/accounts/verify_credentials",
          account,
          ["read:accounts"]
        )

      {:ok, resp} = Router.handle(req)
      assert resp.status == 200

      body = Jason.decode!(resp.body)
      assert body["id"] == "42"
      assert body["username"] == "alice"
      assert body["followers_count"] == 3
      assert body["following_count"] == 5
      assert body["statuses_count"] == 12
      assert is_map(body["source"])
      assert body["scopes"] == ["read:accounts"]
    end

    test "client_credentials token (no account) → 403" do
      req = authed_request("GET", "/api/v1/accounts/verify_credentials", nil, ["read:accounts"])

      {:ok, resp} = Router.handle(req)
      assert resp.status == 403
    end
  end

  describe "GET /api/v1/accounts/:id" do
    test "renders public Account JSON for known id" do
      account = account_fixture(7, "bob")

      Application.put_env(:sukhi_api, :fake_accounts, %{
        get_account: {:ok, account},
        counts_for: %{followers: 0, following: 0, statuses: 0}
      })

      {:ok, resp} =
        Router.handle(%{
          method: "GET",
          path: "/api/v1/accounts/7",
          headers: []
        })

      assert resp.status == 200
      body = Jason.decode!(resp.body)
      assert body["id"] == "7"
      assert body["username"] == "bob"
      refute Map.has_key?(body, "source")
    end

    test "404 on unknown id" do
      Application.put_env(:sukhi_api, :fake_accounts, %{
        get_account: {:error, :not_found}
      })

      {:ok, resp} =
        Router.handle(%{
          method: "GET",
          path: "/api/v1/accounts/99999",
          headers: []
        })

      assert resp.status == 404
    end
  end

  describe "GET /api/v1/accounts/lookup" do
    test "returns the account for a local acct" do
      account = account_fixture(3, "carol")

      Application.put_env(:sukhi_api, :fake_accounts, %{
        lookup_by_acct: {:ok, account},
        counts_for: %{followers: 0, following: 0, statuses: 0}
      })

      {:ok, resp} =
        Router.handle(%{
          method: "GET",
          path: "/api/v1/accounts/lookup",
          query: "acct=carol",
          headers: []
        })

      assert resp.status == 200
      assert Jason.decode!(resp.body)["username"] == "carol"
    end

    test "returns 404 for unknown acct" do
      Application.put_env(:sukhi_api, :fake_accounts, %{lookup_by_acct: {:error, :not_found}})

      {:ok, resp} =
        Router.handle(%{
          method: "GET",
          path: "/api/v1/accounts/lookup",
          query: "acct=ghost",
          headers: []
        })

      assert resp.status == 404
    end
  end

  describe "GET /api/v1/accounts/:id/statuses" do
    test "returns paginated status placeholders + Link header" do
      account = account_fixture(2, "dave")

      notes =
        for n <- [3, 2, 1] do
          %{
            id: n,
            content: "note #{n}",
            visibility: "public",
            ap_id: "https://x.example/notes/#{n}",
            cw: nil,
            in_reply_to_ap_id: nil,
            created_at: ~U[2026-04-21 00:00:00Z],
            account: account,
            media: []
          }
        end

      Application.put_env(:sukhi_api, :fake_accounts, %{
        list_statuses: notes
      })

      {:ok, resp} =
        Router.handle(%{
          method: "GET",
          path: "/api/v1/accounts/2/statuses",
          query: "limit=3",
          headers: []
        })

      assert resp.status == 200
      body = Jason.decode!(resp.body)
      assert length(body) == 3
      assert hd(body)["id"] == "3"

      link =
        Enum.find_value(resp.headers, fn {k, v} ->
          if String.downcase(k) == "link", do: v
        end)

      assert link =~ ~s(rel="next")
      assert link =~ "max_id=1"
      assert link =~ ~s(rel="prev")
      assert link =~ "min_id=3"
    end
  end

  describe "GET /api/v1/accounts/relationships" do
    test "returns one Relationship per id" do
      viewer = account_fixture(1, "viewer")

      Application.put_env(:sukhi_api, :fake_social, %{
        list_relationships: [
          %{
            id: 2,
            following: true,
            followed_by: false,
            requested: false,
            showing_reblogs: true,
            notifying: false,
            blocking: false,
            blocked_by: false,
            muting: false,
            muting_notifications: false,
            domain_blocking: false,
            endorsed: false,
            note: ""
          }
        ]
      })

      req =
        authed_request(
          "GET",
          "/api/v1/accounts/relationships",
          viewer,
          ["read:follows"],
          %{query: "id[]=2"}
        )

      {:ok, resp} = Router.handle(req)
      assert resp.status == 200

      [rel] = Jason.decode!(resp.body)
      assert rel["id"] == "2"
      assert rel["following"] == true
    end

    test "401 without token" do
      {:ok, resp} =
        Router.handle(%{
          method: "GET",
          path: "/api/v1/accounts/relationships",
          query: "id[]=1",
          headers: []
        })

      assert resp.status == 401
    end
  end

  describe "PATCH /api/v1/accounts/update_credentials" do
    test "returns updated CredentialAccount" do
      account = account_fixture(5, "eve")
      updated = %{account | display_name: "Eve Updated"}

      Application.put_env(:sukhi_api, :fake_accounts, %{
        update_credentials: {:ok, updated},
        counts_for: %{followers: 0, following: 0, statuses: 0}
      })

      req =
        authed_request(
          "PATCH",
          "/api/v1/accounts/update_credentials",
          account,
          ["write:accounts"],
          %{body: Jason.encode!(%{"display_name" => "Eve Updated"})}
        )

      {:ok, resp} = Router.handle(req)
      assert resp.status == 200
      assert Jason.decode!(resp.body)["display_name"] == "Eve Updated"
    end

    test "validation_failed → 422 with details" do
      account = account_fixture(5, "eve")

      Application.put_env(:sukhi_api, :fake_accounts, %{
        update_credentials: {:error, {:validation, %{display_name: ["is too long"]}}}
      })

      req =
        authed_request(
          "PATCH",
          "/api/v1/accounts/update_credentials",
          account,
          ["write:accounts"],
          %{body: Jason.encode!(%{"display_name" => String.duplicate("x", 200)})}
        )

      {:ok, resp} = Router.handle(req)
      assert resp.status == 422
      body = Jason.decode!(resp.body)
      assert body["error"] == "validation_failed"
      assert body["details"]["display_name"] == ["is too long"]
    end
  end

  defp restore(key, nil), do: Application.delete_env(:sukhi_api, key)
  defp restore(key, value), do: Application.put_env(:sukhi_api, key, value)
end
