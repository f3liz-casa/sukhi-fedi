# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Views.MastodonMediaTest do
  use ExUnit.Case, async: true

  alias SukhiApi.Views.MastodonMedia

  # test config の domain は localhost:4000 (config.exs)

  defp media(attrs) do
    Map.merge(
      %{id: 7, type: "image", url: nil, remote_url: nil, description: nil, blurhash: nil},
      attrs
    )
  end

  describe "remote attachments go through the media proxy" do
    test "url and preview_url are rewritten, remote_url keeps the original" do
      remote = "https://remote.example/files/cat.png"
      out = MastodonMedia.render(media(%{url: remote, remote_url: remote}))

      # 拡張子は CF の edge cache 判定(拡張子ベース)のための飾り
      assert out.url == "https://localhost:4000/proxy/media/7.png"
      assert out.preview_url == out.url
      assert out.remote_url == remote
    end

    test "an extension-less or query-laden source still proxies, just without the suffix" do
      remote = "https://remote.example/files/abc?dl=1"
      out = MastodonMedia.render(media(%{url: remote, remote_url: remote}))

      assert out.url == "https://localhost:4000/proxy/media/7"
    end

    test "local uploads are served directly, not proxied" do
      out = MastodonMedia.render(media(%{url: "/uploads/1/abc.png"}))

      assert out.url == "/uploads/1/abc.png"
      assert out.remote_url == nil
    end
  end
end
