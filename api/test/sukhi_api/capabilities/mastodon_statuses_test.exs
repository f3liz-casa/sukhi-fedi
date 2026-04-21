# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MastodonStatusesTest do
  use ExUnit.Case, async: false

  alias SukhiApi.Router

  defmodule FakeRpc do
    def call(mod, fun, args), do: call(mod, fun, args, 5_000)

    def call(SukhiFedi.Notes, fun, args, _t), do: lookup(:fake_notes, fun, args)
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
      notes: Application.get_env(:sukhi_api, :fake_notes),
      oauth: Application.get_env(:sukhi_api, :fake_oauth)
    }

    Application.put_env(:sukhi_api, :gateway_rpc_impl, FakeRpc)
    Application.put_env(:sukhi_api, :enabled_addons, :all)
    Application.put_env(:sukhi_api, :fake_notes, %{})

    on_exit(fn ->
      restore(:gateway_rpc_impl, prev.rpc)
      restore(:enabled_addons, prev.addons)
      restore(:fake_notes, prev.notes)
      restore(:fake_oauth, prev.oauth)
    end)

    :ok
  end

  defp account_fixture, do: %{id: 1, username: "alice", display_name: "Alice", summary: "", is_bot: false}

  defp note_fixture(attrs \\ %{}) do
    Map.merge(
      %{
        id: 100,
        content: "hello",
        visibility: "public",
        ap_id: "https://x.example/notes/100",
        cw: nil,
        in_reply_to_ap_id: nil,
        created_at: ~U[2026-04-21 00:00:00Z],
        account: account_fixture(),
        media: []
      },
      attrs
    )
  end

  defp authed_request(method, path, scopes, extra \\ %{}) do
    Application.put_env(:sukhi_api, :fake_oauth, %{
      verify_bearer:
        {:ok, %{account: account_fixture(), app: %{id: 1, name: "x"}, scopes: scopes}}
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

  describe "POST /api/v1/statuses" do
    test "happy path returns Status JSON" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        create_status: {:ok, note_fixture()}
      })

      req =
        authed_request(
          "POST",
          "/api/v1/statuses",
          ["write:statuses"],
          %{body: Jason.encode!(%{"status" => "hello"})}
        )

      {:ok, resp} = Router.handle(req)
      assert resp.status == 200

      body = Jason.decode!(resp.body)
      assert body["id"] == "100"
      assert body["content"] =~ "hello"
      assert body["visibility"] == "public"
      assert body["account"]["username"] == "alice"
      assert body["media_attachments"] == []
    end

    test "validation error → 422" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        create_status: {:error, {:validation, %{content: ["can't be blank"]}}}
      })

      req =
        authed_request(
          "POST",
          "/api/v1/statuses",
          ["write:statuses"],
          %{body: Jason.encode!(%{})}
        )

      {:ok, resp} = Router.handle(req)
      assert resp.status == 422
      assert Jason.decode!(resp.body)["error"] == "validation_failed"
    end

    test "media_not_owned → 422" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        create_status: {:error, :media_not_owned}
      })

      req =
        authed_request(
          "POST",
          "/api/v1/statuses",
          ["write:statuses"],
          %{body: Jason.encode!(%{"status" => "x", "media_ids" => ["999"]})}
        )

      {:ok, resp} = Router.handle(req)
      assert resp.status == 422
    end

    test "direct visibility → 422" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        create_status: {:error, :direct_visibility_not_supported}
      })

      req =
        authed_request(
          "POST",
          "/api/v1/statuses",
          ["write:statuses"],
          %{body: Jason.encode!(%{"status" => "x", "visibility" => "direct"})}
        )

      {:ok, resp} = Router.handle(req)
      assert resp.status == 422
    end

    test "missing token → 401" do
      {:ok, resp} =
        Router.handle(%{
          method: "POST",
          path: "/api/v1/statuses",
          headers: [],
          body: Jason.encode!(%{"status" => "x"})
        })

      assert resp.status == 401
    end

    test "form-encoded body with media_ids[]= is normalized" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        create_status: {:ok, note_fixture()}
      })

      req =
        authed_request(
          "POST",
          "/api/v1/statuses",
          ["write:statuses"],
          %{
            headers: [
              {"authorization", "Bearer t"},
              {"content-type", "application/x-www-form-urlencoded"}
            ],
            body: "status=hi&media_ids%5B%5D=1&media_ids%5B%5D=2"
          }
        )

      {:ok, resp} = Router.handle(req)
      assert resp.status == 200
    end
  end

  describe "GET /api/v1/statuses/:id" do
    test "returns Status JSON for known id" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        get_note: {:ok, note_fixture(%{id: 7, content: "<p>hi</p>"})}
      })

      {:ok, resp} = Router.handle(%{method: "GET", path: "/api/v1/statuses/7", headers: []})

      assert resp.status == 200
      assert Jason.decode!(resp.body)["id"] == "7"
    end

    test "404 on unknown id" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        get_note: {:error, :not_found}
      })

      {:ok, resp} = Router.handle(%{method: "GET", path: "/api/v1/statuses/9999", headers: []})

      assert resp.status == 404
    end
  end

  describe "DELETE /api/v1/statuses/:id" do
    test "owner can delete; returns the deleted status" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        delete_note: {:ok, note_fixture(%{id: 7})}
      })

      req = authed_request("DELETE", "/api/v1/statuses/7", ["write:statuses"])
      {:ok, resp} = Router.handle(req)

      assert resp.status == 200
      assert Jason.decode!(resp.body)["id"] == "7"
    end

    test "non-owner → 403" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        delete_note: {:error, :forbidden}
      })

      req = authed_request("DELETE", "/api/v1/statuses/7", ["write:statuses"])
      {:ok, resp} = Router.handle(req)

      assert resp.status == 403
    end

    test "unknown id → 404" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        delete_note: {:error, :not_found}
      })

      req = authed_request("DELETE", "/api/v1/statuses/9999", ["write:statuses"])
      {:ok, resp} = Router.handle(req)

      assert resp.status == 404
    end
  end

  describe "GET /api/v1/statuses/:id/context" do
    test "returns ancestors and descendants arrays" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        context: {:ok, %{ancestors: [note_fixture(%{id: 1})], descendants: [note_fixture(%{id: 3}), note_fixture(%{id: 4})]}}
      })

      {:ok, resp} =
        Router.handle(%{method: "GET", path: "/api/v1/statuses/2/context", headers: []})

      assert resp.status == 200
      body = Jason.decode!(resp.body)
      assert length(body["ancestors"]) == 1
      assert length(body["descendants"]) == 2
    end

    test "404 on unknown root id" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        context: {:error, :not_found}
      })

      {:ok, resp} =
        Router.handle(%{method: "GET", path: "/api/v1/statuses/9999/context", headers: []})

      assert resp.status == 404
    end
  end

  defp restore(key, nil), do: Application.delete_env(:sukhi_api, key)
  defp restore(key, value), do: Application.put_env(:sukhi_api, key, value)
end
