# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.HTMLTest do
  use ExUnit.Case, async: true

  # Pure unit test (no DB), but the project's runner filters to
  # `--only integration`, so opt in to be picked up.
  @moduletag :integration

  alias SukhiFedi.HTML

  describe "sanitize/1 strips XSS vectors" do
    test "drops event-handler-bearing tags" do
      refute HTML.sanitize(~s|<p>hi <img src=x onerror=alert(1)> end</p>|) =~ "onerror"
      assert HTML.sanitize(~s|<svg onload=alert(1)></svg>|) == ""
    end

    test "drops script tags (content survives only as inert text)" do
      out = HTML.sanitize(~s|<script>alert(1)</script>ok|)
      refute out =~ "<script"
      assert out =~ "ok"
    end

    test "drops javascript: and data: URIs on links" do
      refute HTML.sanitize(~s|<a href="javascript:evil()">x</a>|) =~ "javascript:"
      refute HTML.sanitize(~s|<a href="data:text/html,xx">x</a>|) =~ "data:"
    end

    test "escapes bare angle brackets / ampersands" do
      assert HTML.sanitize("a < b & c") == "a &lt; b &amp; c"
    end
  end

  describe "sanitize/1 keeps the Mastodon allow-list" do
    test "keeps mention links with class/rel and https href" do
      html = ~s|<a href="https://ok.example/@u" class="mention" rel="nofollow">@u</a>|
      out = HTML.sanitize(html)
      assert out =~ ~s|href="https://ok.example/@u"|
      assert out =~ ~s|class="mention"|
      assert out =~ ~s|rel="nofollow"|
    end

    test "keeps span[class], ruby annotations and basic formatting" do
      assert HTML.sanitize(~s|<span class="h-card">t</span>|) =~ ~s|<span class="h-card">|
      assert HTML.sanitize("<ruby>漢<rt>かん</rt></ruby>") == "<ruby>漢<rt>かん</rt></ruby>"

      assert HTML.sanitize("<p>a <strong>b</strong> <em>c</em></p>") ==
               "<p>a <strong>b</strong> <em>c</em></p>"
    end
  end

  describe "sanitize/1 passthrough" do
    test "leaves plain text and non-binaries untouched" do
      assert HTML.sanitize("just text") == "just text"
      assert HTML.sanitize(nil) == nil
    end
  end
end
