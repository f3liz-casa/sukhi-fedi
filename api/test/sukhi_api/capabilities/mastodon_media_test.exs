# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MastodonMediaTest do
  use ExUnit.Case, async: false

  alias SukhiApi.Router

  defmodule FakeRpc do
    def call(mod, fun, args), do: call(mod, fun, args, 5_000)

    def call(SukhiFedi.Addons.Media, fun, args, _t), do: lookup(:fake_media, fun, args)
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
      media: Application.get_env(:sukhi_api, :fake_media),
      oauth: Application.get_env(:sukhi_api, :fake_oauth)
    }

    Application.put_env(:sukhi_api, :gateway_rpc_impl, FakeRpc)
    Application.put_env(:sukhi_api, :enabled_addons, :all)
    Application.put_env(:sukhi_api, :fake_media, %{})

    on_exit(fn ->
      restore(:gateway_rpc_impl, prev.rpc)
      restore(:enabled_addons, prev.addons)
      restore(:fake_media, prev.media)
      restore(:fake_oauth, prev.oauth)
    end)

    :ok
  end

  defp account, do: %{id: 1, username: "alice"}

  defp media_fixture(attrs \\ %{}) do
    Map.merge(
      %{
        id: 7,
        url: "http://localhost:4000/uploads/1/abc.png",
        type: "image",
        description: "test",
        blurhash: nil,
        width: nil,
        height: nil,
        remote_url: nil,
        attached_at: nil
      },
      attrs
    )
  end

  defp authed(method, path, scopes, extra \\ %{}) do
    Application.put_env(:sukhi_api, :fake_oauth, %{
      verify_bearer:
        {:ok, %{account: account(), app: %{id: 1, name: "x"}, scopes: scopes}}
    })

    Map.merge(
      %{method: method, path: path, headers: [{"authorization", "Bearer t"}]},
      extra
    )
  end

  defp multipart_body(boundary, parts) do
    delim = "--" <> boundary

    Enum.map_join(parts, "", fn p -> delim <> "\r\n" <> p <> "\r\n" end) <>
      delim <> "--\r\n"
  end

  describe "POST /api/v1/media" do
    test "happy path returns 200 with MediaAttachment JSON" do
      Application.put_env(:sukhi_api, :fake_media, %{
        create_from_upload: {:ok, media_fixture(%{id: 42})}
      })

      body =
        multipart_body("BB", [
          ~s|Content-Disposition: form-data; name="file"; filename="x.png"\r\nContent-Type: image/png\r\n\r\n| <>
            "PNG_BYTES",
          ~s|Content-Disposition: form-data; name="description"\r\n\r\na photo|
        ])

      req =
        authed("POST", "/api/v1/media", ["write:media"], %{
          headers: [
            {"authorization", "Bearer t"},
            {"content-type", "multipart/form-data; boundary=BB"}
          ],
          body: body
        })

      {:ok, resp} = Router.handle(req)
      assert resp.status == 200

      json = Jason.decode!(resp.body)
      assert json["id"] == "42"
      assert json["type"] == "image"
      assert json["url"] =~ "uploads/"
    end

    test "POST /api/v2/media returns 202" do
      Application.put_env(:sukhi_api, :fake_media, %{
        create_from_upload: {:ok, media_fixture()}
      })

      body =
        multipart_body("BB", [
          ~s|Content-Disposition: form-data; name="file"; filename="x.png"\r\nContent-Type: image/png\r\n\r\n| <>
            "PNG"
        ])

      req =
        authed("POST", "/api/v2/media", ["write:media"], %{
          headers: [
            {"authorization", "Bearer t"},
            {"content-type", "multipart/form-data; boundary=BB"}
          ],
          body: body
        })

      {:ok, resp} = Router.handle(req)
      assert resp.status == 202
    end

    test "missing file part → 422" do
      body =
        multipart_body("BB", [
          ~s|Content-Disposition: form-data; name="description"\r\n\r\nno file|
        ])

      req =
        authed("POST", "/api/v1/media", ["write:media"], %{
          headers: [
            {"authorization", "Bearer t"},
            {"content-type", "multipart/form-data; boundary=BB"}
          ],
          body: body
        })

      {:ok, resp} = Router.handle(req)
      assert resp.status == 422
    end

    test "wrong content-type → 415" do
      req =
        authed("POST", "/api/v1/media", ["write:media"], %{
          headers: [{"authorization", "Bearer t"}, {"content-type", "application/json"}],
          body: "{}"
        })

      {:ok, resp} = Router.handle(req)
      assert resp.status == 415
    end

    test "file_too_large from gateway → 413" do
      Application.put_env(:sukhi_api, :fake_media, %{
        create_from_upload: {:error, :file_too_large}
      })

      body =
        multipart_body("BB", [
          ~s|Content-Disposition: form-data; name="file"; filename="x.bin"\r\nContent-Type: application/octet-stream\r\n\r\n| <>
            "anything"
        ])

      req =
        authed("POST", "/api/v1/media", ["write:media"], %{
          headers: [
            {"authorization", "Bearer t"},
            {"content-type", "multipart/form-data; boundary=BB"}
          ],
          body: body
        })

      {:ok, resp} = Router.handle(req)
      assert resp.status == 413
    end

    test "missing token → 401" do
      {:ok, resp} =
        Router.handle(%{
          method: "POST",
          path: "/api/v1/media",
          headers: [{"content-type", "multipart/form-data; boundary=BB"}],
          body: ""
        })

      assert resp.status == 401
    end
  end

  describe "GET /api/v1/media/:id" do
    test "owner gets 200" do
      Application.put_env(:sukhi_api, :fake_media, %{
        get_media: {:ok, media_fixture(%{id: 9})}
      })

      req = authed("GET", "/api/v1/media/9", ["read:media"])
      {:ok, resp} = Router.handle(req)

      assert resp.status == 200
      assert Jason.decode!(resp.body)["id"] == "9"
    end

    test "non-owner → 403" do
      Application.put_env(:sukhi_api, :fake_media, %{
        get_media: {:error, :forbidden}
      })

      req = authed("GET", "/api/v1/media/9", ["read:media"])
      {:ok, resp} = Router.handle(req)
      assert resp.status == 403
    end

    test "404 on unknown id" do
      Application.put_env(:sukhi_api, :fake_media, %{
        get_media: {:error, :not_found}
      })

      req = authed("GET", "/api/v1/media/999", ["read:media"])
      {:ok, resp} = Router.handle(req)
      assert resp.status == 404
    end
  end

  describe "PUT /api/v1/media/:id" do
    test "updates description" do
      Application.put_env(:sukhi_api, :fake_media, %{
        update_media: {:ok, media_fixture(%{description: "updated"})}
      })

      req =
        authed("PUT", "/api/v1/media/7", ["write:media"], %{
          headers: [{"authorization", "Bearer t"}, {"content-type", "application/json"}],
          body: Jason.encode!(%{"description" => "updated"})
        })

      {:ok, resp} = Router.handle(req)
      assert resp.status == 200
      assert Jason.decode!(resp.body)["description"] == "updated"
    end

    test "already_attached → 422" do
      Application.put_env(:sukhi_api, :fake_media, %{
        update_media: {:error, :already_attached}
      })

      req =
        authed("PUT", "/api/v1/media/7", ["write:media"], %{
          headers: [{"authorization", "Bearer t"}, {"content-type", "application/json"}],
          body: Jason.encode!(%{"description" => "x"})
        })

      {:ok, resp} = Router.handle(req)
      assert resp.status == 422
    end
  end

  defp restore(key, nil), do: Application.delete_env(:sukhi_api, key)
  defp restore(key, value), do: Application.put_env(:sukhi_api, key, value)
end
