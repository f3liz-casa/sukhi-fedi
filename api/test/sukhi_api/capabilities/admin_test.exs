# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.AdminTest do
  use ExUnit.Case, async: false

  alias SukhiApi.Router

  defmodule FakeRpc do
    def call(mod, fun, args), do: call(mod, fun, args, 5_000)

    def call(SukhiFedi.Accounts, fun, args, _t), do: lookup(:fake_accounts, fun, args)
    def call(SukhiFedi.Addons.Moderation, fun, args, _t), do: lookup(:fake_moderation, fun, args)
    def call(SukhiFedi.Stats, fun, args, _t), do: lookup(:fake_stats, fun, args)
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
      moderation: Application.get_env(:sukhi_api, :fake_moderation),
      stats: Application.get_env(:sukhi_api, :fake_stats),
      oauth: Application.get_env(:sukhi_api, :fake_oauth)
    }

    Application.put_env(:sukhi_api, :gateway_rpc_impl, FakeRpc)
    Application.put_env(:sukhi_api, :enabled_addons, :all)
    Application.put_env(:sukhi_api, :fake_accounts, %{})
    Application.put_env(:sukhi_api, :fake_moderation, %{})
    Application.put_env(:sukhi_api, :fake_stats, %{})

    on_exit(fn ->
      restore(:gateway_rpc_impl, prev.rpc)
      restore(:enabled_addons, prev.addons)
      restore(:fake_accounts, prev.accounts)
      restore(:fake_moderation, prev.moderation)
      restore(:fake_stats, prev.stats)
      restore(:fake_oauth, prev.oauth)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:sukhi_api, key)
  defp restore(key, v), do: Application.put_env(:sukhi_api, key, v)

  defp admin_fixture(id \\ 1) do
    %{
      id: id,
      username: "root",
      display_name: "Root",
      summary: "",
      is_bot: false,
      is_admin: true,
      avatar_url: nil,
      banner_url: nil,
      suspended_at: nil,
      suspended_by_id: nil,
      suspension_reason: nil,
      created_at: ~U[2026-01-01 00:00:00Z]
    }
  end

  defp user_fixture(id, username, overrides \\ %{}) do
    Map.merge(
      %{
        id: id,
        username: username,
        display_name: String.capitalize(username),
        summary: "",
        is_bot: false,
        is_admin: false,
        avatar_url: nil,
        banner_url: nil,
        suspended_at: nil,
        suspended_by_id: nil,
        suspension_reason: nil,
        created_at: ~U[2026-01-01 00:00:00Z]
      },
      overrides
    )
  end

  defp authed(method, path, account, scopes, extra \\ %{}) do
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

  # ── auth ────────────────────────────────────────────────────────────────

  describe "authorization" do
    test "no token → 401" do
      req = %{method: "GET", path: "/api/admin/accounts", headers: []}
      {:ok, resp} = Router.handle(req)
      assert resp.status == 401
    end

    test "token without admin:read → 403 insufficient_scope" do
      req = authed("GET", "/api/admin/accounts", admin_fixture(), ["read:accounts"])
      {:ok, resp} = Router.handle(req)
      assert resp.status == 403
      body = Jason.decode!(resp.body)
      assert body["error"] == "insufficient_scope"
    end

    test "admin:read scope but non-admin account → 403 admin_required" do
      non_admin = user_fixture(2, "alice")
      req = authed("GET", "/api/admin/accounts", non_admin, ["admin:read"])
      {:ok, resp} = Router.handle(req)
      assert resp.status == 403
      assert Jason.decode!(resp.body)["error"] == "admin_required"
    end
  end

  # ── accounts ────────────────────────────────────────────────────────────

  describe "GET /api/admin/accounts" do
    test "returns items + pagination meta" do
      users = [user_fixture(10, "alice"), user_fixture(11, "bob")]

      Application.put_env(:sukhi_api, :fake_accounts, %{
        list_accounts: {:ok, {users, 42}}
      })

      req = authed("GET", "/api/admin/accounts", admin_fixture(), ["admin:read"], %{query: ""})
      {:ok, resp} = Router.handle(req)
      assert resp.status == 200

      body = Jason.decode!(resp.body)
      assert length(body["items"]) == 2
      assert body["pagination"] == %{"page" => 1, "per_page" => 20, "total" => 42, "total_pages" => 3}
      assert Enum.at(body["items"], 0)["username"] == "alice"
      assert Enum.at(body["items"], 0)["is_admin"] == false
    end

    test "clamps per_page > 100 to 100" do
      Application.put_env(:sukhi_api, :fake_accounts, %{list_accounts: {:ok, {[], 0}}})

      req =
        authed("GET", "/api/admin/accounts", admin_fixture(), ["admin:read"], %{
          query: "per_page=9999&page=0"
        })

      {:ok, resp} = Router.handle(req)
      body = Jason.decode!(resp.body)
      assert body["pagination"]["per_page"] == 100
      assert body["pagination"]["page"] == 1
    end
  end

  describe "POST /api/admin/accounts/:id/suspend" do
    test "suspends and returns admin account" do
      suspended =
        user_fixture(10, "alice", %{
          suspended_at: ~U[2026-04-21 12:00:00Z],
          suspended_by_id: 1,
          suspension_reason: "spam"
        })

      Application.put_env(:sukhi_api, :fake_moderation, %{
        suspend_account: {:ok, suspended}
      })

      req =
        authed("POST", "/api/admin/accounts/10/suspend", admin_fixture(), ["admin:write"], %{
          body: Jason.encode!(%{"reason" => "spam"})
        })

      {:ok, resp} = Router.handle(req)
      assert resp.status == 200

      body = Jason.decode!(resp.body)
      assert body["suspended"] == true
      assert body["suspension_reason"] == "spam"
      assert body["suspended_by_id"] == "1"
    end

    test "404 on missing account" do
      Application.put_env(:sukhi_api, :fake_moderation, %{suspend_account: {:error, :not_found}})

      req =
        authed("POST", "/api/admin/accounts/999/suspend", admin_fixture(), ["admin:write"], %{
          body: "{}"
        })

      {:ok, resp} = Router.handle(req)
      assert resp.status == 404
    end
  end

  describe "POST /api/admin/accounts/:id/promote + demote" do
    test "promote sets is_admin true" do
      promoted = user_fixture(10, "alice", %{is_admin: true})

      Application.put_env(:sukhi_api, :fake_accounts, %{set_admin: {:ok, promoted}})

      req = authed("POST", "/api/admin/accounts/10/promote", admin_fixture(), ["admin:write"])
      {:ok, resp} = Router.handle(req)
      assert resp.status == 200
      assert Jason.decode!(resp.body)["is_admin"] == true
    end

    test "demote sets is_admin false" do
      demoted = user_fixture(10, "alice", %{is_admin: false})

      Application.put_env(:sukhi_api, :fake_accounts, %{set_admin: {:ok, demoted}})

      req = authed("POST", "/api/admin/accounts/10/demote", admin_fixture(), ["admin:write"])
      {:ok, resp} = Router.handle(req)
      assert resp.status == 200
      assert Jason.decode!(resp.body)["is_admin"] == false
    end
  end

  # ── reports ─────────────────────────────────────────────────────────────

  describe "GET /api/admin/reports" do
    test "defaults to status=open, paginated" do
      reports = [
        %{
          id: 1,
          status: "open",
          comment: "spam",
          account: user_fixture(2, "reporter"),
          target: user_fixture(3, "bad"),
          note: nil,
          resolved_at: nil,
          resolved_by: nil,
          inserted_at: ~U[2026-04-20 10:00:00Z]
        }
      ]

      Application.put_env(:sukhi_api, :fake_moderation, %{
        {:list_reports, ["open", %{page: 1, per_page: 20, offset: 0, limit: 20}]} =>
          {:ok, {reports, 1}}
      })

      req = authed("GET", "/api/admin/reports", admin_fixture(), ["admin:read"], %{query: ""})
      {:ok, resp} = Router.handle(req)
      assert resp.status == 200

      body = Jason.decode!(resp.body)
      assert [report] = body["items"]
      assert report["status"] == "open"
      assert report["reporter"]["username"] == "reporter"
      assert report["target"]["username"] == "bad"
    end
  end

  describe "POST /api/admin/reports/:id/resolve" do
    test "marks report resolved" do
      resolved = %{
        id: 1,
        status: "resolved",
        comment: "spam",
        account: user_fixture(2, "reporter"),
        target: user_fixture(3, "bad"),
        note: nil,
        resolved_at: ~U[2026-04-21 12:00:00Z],
        resolved_by: admin_fixture(),
        inserted_at: ~U[2026-04-20 10:00:00Z]
      }

      Application.put_env(:sukhi_api, :fake_moderation, %{
        resolve_report: {:ok, resolved},
        get_report: {:ok, resolved}
      })

      req = authed("POST", "/api/admin/reports/1/resolve", admin_fixture(), ["admin:write"])
      {:ok, resp} = Router.handle(req)
      assert resp.status == 200

      body = Jason.decode!(resp.body)
      assert body["status"] == "resolved"
      assert body["resolved_by"]["username"] == "root"
    end
  end

  # ── domain blocks ───────────────────────────────────────────────────────

  describe "POST /api/admin/domain_blocks" do
    test "creates a block" do
      block = %{
        id: 5,
        domain: "evil.example",
        severity: "suspend",
        reason: "spam",
        created_by_id: 1,
        inserted_at: ~U[2026-04-21 12:00:00Z]
      }

      Application.put_env(:sukhi_api, :fake_moderation, %{block_instance: {:ok, block}})

      req =
        authed("POST", "/api/admin/domain_blocks", admin_fixture(), ["admin:write"], %{
          body: Jason.encode!(%{"domain" => "Evil.Example", "severity" => "suspend", "reason" => "spam"})
        })

      {:ok, resp} = Router.handle(req)
      assert resp.status == 200

      body = Jason.decode!(resp.body)
      assert body["domain"] == "evil.example"
      assert body["severity"] == "suspend"
    end

    test "missing domain → 422" do
      req =
        authed("POST", "/api/admin/domain_blocks", admin_fixture(), ["admin:write"], %{
          body: "{}"
        })

      {:ok, resp} = Router.handle(req)
      assert resp.status == 422
    end
  end

  describe "DELETE /api/admin/domain_blocks" do
    test "unblocks by domain query string" do
      Application.put_env(:sukhi_api, :fake_moderation, %{
        unblock_instance: {:ok, %{domain: "evil.example"}}
      })

      req =
        authed("DELETE", "/api/admin/domain_blocks", admin_fixture(), ["admin:write"], %{
          query: "domain=evil.example"
        })

      {:ok, resp} = Router.handle(req)
      assert resp.status == 200
      assert Jason.decode!(resp.body)["domain"] == "evil.example"
    end

    test "missing domain → 422" do
      req =
        authed("DELETE", "/api/admin/domain_blocks", admin_fixture(), ["admin:write"], %{
          query: ""
        })

      {:ok, resp} = Router.handle(req)
      assert resp.status == 422
    end

    test "unknown domain → 404" do
      Application.put_env(:sukhi_api, :fake_moderation, %{
        unblock_instance: {:error, :not_found}
      })

      req =
        authed("DELETE", "/api/admin/domain_blocks", admin_fixture(), ["admin:write"], %{
          query: "domain=nope.example"
        })

      {:ok, resp} = Router.handle(req)
      assert resp.status == 404
    end
  end

  # ── stats ───────────────────────────────────────────────────────────────

  describe "GET /api/admin/stats" do
    test "returns dashboard payload" do
      payload = %{
        accounts: %{total: 100, local: 100, remote: 0, suspended: 1, admins: 1, active_last_7d: 10, active_last_30d: 50},
        statuses: %{total: 500, local: 500, last_24h: 20, last_7d: 80},
        federation: %{known_domains: 15, blocked_domains: 2},
        moderation: %{open_reports: 3, resolved_reports_7d: 1},
        generated_at: "2026-04-21T12:00:00Z"
      }

      Application.put_env(:sukhi_api, :fake_stats, %{dashboard: payload})

      req = authed("GET", "/api/admin/stats", admin_fixture(), ["admin:read"])
      {:ok, resp} = Router.handle(req)
      assert resp.status == 200

      body = Jason.decode!(resp.body)
      assert body["accounts"]["total"] == 100
      assert body["moderation"]["open_reports"] == 3
      assert body["federation"]["known_domains"] == 15
    end
  end
end
