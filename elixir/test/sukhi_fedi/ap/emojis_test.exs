# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.AP.EmojisTest do
  use ExUnit.Case, async: true

  alias SukhiFedi.AP.Emojis

  describe "from_tag/1" do
    test "maps an Emoji tag to the Mastodon emoji shape, stripping the colons" do
      tag = [
        %{
          "type" => "Emoji",
          "name" => ":blobcat:",
          "icon" => %{"type" => "Image", "url" => "https://misskey.example/e/blobcat.png"}
        }
      ]

      assert Emojis.from_tag(tag) == [
               %{
                 "shortcode" => "blobcat",
                 "url" => "https://misskey.example/e/blobcat.png",
                 "static_url" => "https://misskey.example/e/blobcat.png",
                 "visible_in_picker" => false
               }
             ]
    end

    test "accepts a bare-string icon url" do
      tag = [%{"type" => "Emoji", "name" => ":x:", "icon" => "https://e.example/x.png"}]
      assert [%{"shortcode" => "x", "url" => "https://e.example/x.png"}] = Emojis.from_tag(tag)
    end

    test "ignores Mentions, Hashtags, and emoji without an icon" do
      tag = [
        %{"type" => "Mention", "href" => "https://x.example/users/a"},
        %{"type" => "Hashtag", "name" => "#tag"},
        %{"type" => "Emoji", "name" => ":noicon:"}
      ]

      assert Emojis.from_tag(tag) == []
    end

    test "deduplicates a shortcode the peer lists once per occurrence" do
      skeb = %{
        "type" => "Emoji",
        "name" => ":skeb:",
        "icon" => %{"type" => "Image", "url" => "https://e.example/skeb.png"}
      }

      assert [%{"shortcode" => "skeb"}] = Emojis.from_tag([skeb, skeb, skeb])
    end

    test "non-list input is an empty list" do
      assert Emojis.from_tag(nil) == []
      assert Emojis.from_tag(%{}) == []
    end
  end
end
