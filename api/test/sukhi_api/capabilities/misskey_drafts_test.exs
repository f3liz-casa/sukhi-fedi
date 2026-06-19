# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MisskeyDraftsTest do
  use ExUnit.Case, async: false

  alias SukhiApi.Router

  defmodule FakeRpc do
    def call(mod, fun, args), do: call(mod, fun, args, 5_000)

    def call(SukhiFedi.NoteDrafts, fun, args, _t), do: lookup(:fake_drafts, fun, args)
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
      drafts: Application.get_env(:sukhi_api, :fake_drafts),
      oauth: Application.get_env(:sukhi_api, :fake_oauth)
    }

    Application.put_env(:sukhi_api, :gateway_rpc_impl, FakeRpc)
    Application.put_env(:sukhi_api, :enabled_addons, :all)
    Application.put_env(:sukhi_api, :fake_drafts, %{})

    Application.put_env(:sukhi_api, :fake_oauth, %{
      verify_bearer:
        {:ok,
         %{
           account: %{id: 7, username: "alice", display_name: "A", summary: ""},
           app: %{id: 1, name: "x"},
           scopes: ["read:statuses", "write:statuses"]
         }}
    })

    on_exit(fn ->
      restore(:gateway_rpc_impl, prev.rpc)
      restore(:enabled_addons, prev.addons)
      restore(:fake_drafts, prev.drafts)
      restore(:fake_oauth, prev.oauth)
    end)

    :ok
  end

  defp draft do
    %{
      text: "hi",
      spoiler: "",
      sensitive: false,
      visibility: "public",
      updated_at: ~U[2026-06-19 00:00:00Z]
    }
  end

  defp authed(method, body) do
    %{
      method: method,
      path: "/api/i/notes/drafts",
      headers: [{"authorization", "Bearer t"}, {"content-type", "application/json"}],
      body: body
    }
  end

  describe "GET /api/i/notes/drafts" do
    test "renders the stored draft in ComposeDraft shape" do
      Application.put_env(:sukhi_api, :fake_drafts, %{{:get, [7]} => draft()})

      {:ok, resp} = Router.handle(authed("GET", nil))

      assert resp.status == 200
      body = JSON.decode!(resp.body)
      assert body["text"] == "hi"
      assert body["useSpoiler"] == false
      assert body["visibility"] == "public"
    end

    test "no draft → 204" do
      Application.put_env(:sukhi_api, :fake_drafts, %{{:get, [7]} => nil})

      {:ok, resp} = Router.handle(authed("GET", nil))
      assert resp.status == 204
    end

    test "missing token → 401" do
      {:ok, resp} =
        Router.handle(%{method: "GET", path: "/api/i/notes/drafts", headers: []})

      assert resp.status == 401
    end
  end

  describe "PUT /api/i/notes/drafts" do
    test "upserts the composer body and renders the saved draft" do
      attrs = %{
        "text" => "hi",
        "spoiler" => "",
        "sensitive" => false,
        "visibility" => "public"
      }

      Application.put_env(:sukhi_api, :fake_drafts, %{{:upsert, [7, attrs]} => {:ok, draft()}})

      {:ok, resp} =
        Router.handle(
          authed("PUT", JSON.encode!(%{text: "hi", useSpoiler: false, visibility: "public"}))
        )

      assert resp.status == 200
      assert JSON.decode!(resp.body)["text"] == "hi"
    end
  end

  describe "DELETE /api/i/notes/drafts" do
    test "discards the draft → 200" do
      Application.put_env(:sukhi_api, :fake_drafts, %{{:delete, [7]} => :ok})

      {:ok, resp} = Router.handle(authed("DELETE", nil))
      assert resp.status == 200
    end
  end

  defp restore(key, nil), do: Application.delete_env(:sukhi_api, key)
  defp restore(key, value), do: Application.put_env(:sukhi_api, key, value)
end
