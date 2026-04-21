# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MastodonInteractionsTest do
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

  defp account, do: %{id: 1, username: "alice", display_name: "A", summary: "", is_bot: false}

  defp note(attrs \\ %{}) do
    Map.merge(
      %{
        id: 100,
        content: "hi",
        visibility: "public",
        ap_id: "https://x.example/notes/100",
        cw: nil,
        in_reply_to_ap_id: nil,
        created_at: ~U[2026-04-21 00:00:00Z],
        account: account(),
        media: []
      },
      attrs
    )
  end

  defp authed(method, path, scopes) do
    Application.put_env(:sukhi_api, :fake_oauth, %{
      verify_bearer:
        {:ok, %{account: account(), app: %{id: 1, name: "x"}, scopes: scopes}}
    })

    %{
      method: method,
      path: path,
      headers: [{"authorization", "Bearer t"}],
      body: ""
    }
  end

  describe "POST /api/v1/statuses/:id/favourite" do
    test "returns Status JSON with favourited=true" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        favourite: {:ok, note()},
        counts_for_note: %{replies: 0, reblogs: 0, favourites: 1},
        viewer_flags: %{favourited: true, reblogged: false, bookmarked: false, pinned: false}
      })

      req = authed("POST", "/api/v1/statuses/100/favourite", ["write:favourites"])
      {:ok, resp} = Router.handle(req)

      assert resp.status == 200
      body = Jason.decode!(resp.body)
      assert body["favourited"] == true
      assert body["favourites_count"] == 1
    end

    test "404 on unknown id" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        favourite: {:error, :not_found}
      })

      req = authed("POST", "/api/v1/statuses/999/favourite", ["write:favourites"])
      {:ok, resp} = Router.handle(req)
      assert resp.status == 404
    end

    test "401 without token" do
      {:ok, resp} =
        Router.handle(%{
          method: "POST",
          path: "/api/v1/statuses/100/favourite",
          headers: []
        })

      assert resp.status == 401
    end
  end

  describe "POST /api/v1/statuses/:id/unfavourite" do
    test "returns Status with favourited=false" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        unfavourite: {:ok, note()},
        counts_for_note: %{replies: 0, reblogs: 0, favourites: 0},
        viewer_flags: %{favourited: false, reblogged: false, bookmarked: false, pinned: false}
      })

      req = authed("POST", "/api/v1/statuses/100/unfavourite", ["write:favourites"])
      {:ok, resp} = Router.handle(req)

      assert resp.status == 200
      assert Jason.decode!(resp.body)["favourited"] == false
    end
  end

  describe "POST /api/v1/statuses/:id/reblog" do
    test "returns Status with reblogged=true and reblogs_count" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        reblog: {:ok, note()},
        counts_for_note: %{replies: 0, reblogs: 1, favourites: 0},
        viewer_flags: %{favourited: false, reblogged: true, bookmarked: false, pinned: false}
      })

      req = authed("POST", "/api/v1/statuses/100/reblog", ["write:statuses"])
      {:ok, resp} = Router.handle(req)

      assert resp.status == 200
      body = Jason.decode!(resp.body)
      assert body["reblogged"] == true
      assert body["reblogs_count"] == 1
    end
  end

  describe "POST /api/v1/statuses/:id/bookmark" do
    test "returns Status with bookmarked=true" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        bookmark: {:ok, note()},
        counts_for_note: %{replies: 0, reblogs: 0, favourites: 0},
        viewer_flags: %{favourited: false, reblogged: false, bookmarked: true, pinned: false}
      })

      req = authed("POST", "/api/v1/statuses/100/bookmark", ["write:bookmarks"])
      {:ok, resp} = Router.handle(req)

      assert resp.status == 200
      assert Jason.decode!(resp.body)["bookmarked"] == true
    end
  end

  describe "POST /api/v1/statuses/:id/pin" do
    test "owner can pin" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        pin: {:ok, note()},
        counts_for_note: %{replies: 0, reblogs: 0, favourites: 0},
        viewer_flags: %{favourited: false, reblogged: false, bookmarked: false, pinned: true}
      })

      req = authed("POST", "/api/v1/statuses/100/pin", ["write:accounts"])
      {:ok, resp} = Router.handle(req)
      assert resp.status == 200
      assert Jason.decode!(resp.body)["pinned"] == true
    end

    test "non-owner → 403" do
      Application.put_env(:sukhi_api, :fake_notes, %{pin: {:error, :forbidden}})
      req = authed("POST", "/api/v1/statuses/100/pin", ["write:accounts"])
      {:ok, resp} = Router.handle(req)
      assert resp.status == 403
    end
  end

  describe "GET /api/v1/bookmarks" do
    test "returns paginated list of bookmarked statuses" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        list_bookmarks: [note(%{id: 3}), note(%{id: 2}), note(%{id: 1})],
        counts_for_notes: %{
          1 => %{replies: 0, reblogs: 0, favourites: 0},
          2 => %{replies: 0, reblogs: 0, favourites: 0},
          3 => %{replies: 0, reblogs: 0, favourites: 0}
        },
        viewer_flags_many: %{
          1 => %{favourited: false, reblogged: false, bookmarked: true, pinned: false},
          2 => %{favourited: false, reblogged: false, bookmarked: true, pinned: false},
          3 => %{favourited: false, reblogged: false, bookmarked: true, pinned: false}
        }
      })

      req = authed("GET", "/api/v1/bookmarks", ["read:bookmarks"])
      {:ok, resp} = Router.handle(req)

      assert resp.status == 200
      body = Jason.decode!(resp.body)
      assert length(body) == 3
      assert Enum.all?(body, fn s -> s["bookmarked"] == true end)
    end
  end

  describe "GET /api/v1/favourites" do
    test "returns paginated list of favourited statuses" do
      Application.put_env(:sukhi_api, :fake_notes, %{
        list_favourites: [note(%{id: 5})],
        counts_for_notes: %{5 => %{replies: 0, reblogs: 0, favourites: 1}},
        viewer_flags_many: %{
          5 => %{favourited: true, reblogged: false, bookmarked: false, pinned: false}
        }
      })

      req = authed("GET", "/api/v1/favourites", ["read:favourites"])
      {:ok, resp} = Router.handle(req)

      assert resp.status == 200
      [s] = Jason.decode!(resp.body)
      assert s["id"] == "5"
      assert s["favourited"] == true
    end
  end

  defp restore(key, nil), do: Application.delete_env(:sukhi_api, key)
  defp restore(key, value), do: Application.put_env(:sukhi_api, key, value)
end
