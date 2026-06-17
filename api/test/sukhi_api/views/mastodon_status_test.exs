# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Views.MastodonStatusTest do
  use ExUnit.Case, async: true

  alias SukhiApi.Views.MastodonStatus

  defp note(visibility) do
    %{
      id: 1,
      content: "hi",
      visibility: visibility,
      created_at: ~U[2021-01-01 00:00:00Z],
      account: %{id: 2, username: "alice", display_name: "alice"}
    }
  end

  describe "visibility maps onto the Mastodon StatusPrivacy enum" do
    test "internal \"followers\" becomes \"private\"" do
      assert MastodonStatus.render(note("followers")).visibility == "private"
    end

    test "public / unlisted / direct pass through" do
      assert MastodonStatus.render(note("public")).visibility == "public"
      assert MastodonStatus.render(note("unlisted")).visibility == "unlisted"
      assert MastodonStatus.render(note("direct")).visibility == "direct"
    end

    test "nil or an unknown value falls back to \"public\" (never null)" do
      assert MastodonStatus.render(note(nil)).visibility == "public"
      assert MastodonStatus.render(note("weird")).visibility == "public"
    end
  end

  describe "Article title extension" do
    test "an article carries its title; a plain note renders title: nil" do
      article = Map.put(note("public"), :title, "On calm timelines")
      assert MastodonStatus.render(article).title == "On calm timelines"
      assert MastodonStatus.render(note("public")).title == nil
    end
  end

  describe "a redundant trailing \"RE:\" link is dropped once we show the quote card" do
    defp quoted do
      %{
        id: 42,
        content: "the original",
        visibility: "public",
        created_at: ~U[2021-01-01 00:00:00Z],
        account: %{id: 9, username: "carol", display_name: "carol"}
      }
    end

    defp with_quote(content) do
      note("public")
      |> Map.put(:content, content)
      |> Map.put(:quote_of_ap_id, "https://remote.test/notes/42")
      |> Map.put(:quoted_note, quoted())
    end

    test "hackers.pub's <span class=\"quote-inline\"> reference is lifted out whole" do
      html =
        ~s(<p>NLNet funding news</p>\n<p><span class="quote-inline"><br /><br />RE: <a href="https://hackers.pub/@drfed/019ed3c9">https://hackers.pub/@drfed/019ed3c9</a></span></p>)

      assert MastodonStatus.render(with_quote(html)).content == "<p>NLNet funding news</p>"
    end

    test "the reference on its own paragraph goes away" do
      html =
        ~s(<p>look at this</p><p>RE: <a href="https://remote.test/notes/42">https://remote.test/notes/42</a></p>)

      rendered = MastodonStatus.render(with_quote(html))
      assert rendered.content == "<p>look at this</p>"
      assert rendered.quote != nil
    end

    test "the reference tacked onto the last paragraph after a <br> goes away, keeping the text" do
      html =
        ~s(<p>look at this<br><br>RE: <a href="https://remote.test/notes/42">https://remote.test/notes/42</a></p>)

      assert MastodonStatus.render(with_quote(html)).content == "<p>look at this</p>"
    end

    test "QT: is treated the same as RE:" do
      html = ~s(<p>hi</p><p>QT: <a href="https://x.test/9">x</a></p>)
      assert MastodonStatus.render(with_quote(html)).content == "<p>hi</p>"
    end

    test "a plain trailing link the author meant to keep is left alone" do
      html = ~s(<p>see <a href="https://example.test/doc">the doc</a></p>)
      assert MastodonStatus.render(with_quote(html)).content == html
    end

    test "without a resolved quote card, the RE: link is kept (it's the only reference)" do
      html =
        ~s(<p>hi</p><p>RE: <a href="https://remote.test/notes/42">https://remote.test/notes/42</a></p>)

      note = Map.put(note("public"), :content, html)
      assert MastodonStatus.render(note).content == html
    end
  end

  describe "boost wrapper renders as a reblog Status" do
    defp boost do
      %{
        __boost__: true,
        id: 999,
        boost_id: 7,
        created_at: ~U[2021-02-02 00:00:00Z],
        account: %{id: 5, username: "bob", display_name: "bob"},
        note: note("public")
      }
    end

    test "outer account is the booster, content empty, reblog holds the note" do
      rendered = MastodonStatus.render(boost())

      assert rendered.account.username == "bob"
      assert rendered.content == ""
      assert rendered.reblog != nil
      assert rendered.reblog.content == "<p>hi</p>"
      assert rendered.reblog.account.username == "alice"
    end

    test "outer id is the synthesized cursor, not the boosted note's id" do
      rendered = MastodonStatus.render(boost())
      assert rendered.id == "999"
    end

    test "context_key borrows the boosted note's id for hydration" do
      assert MastodonStatus.context_key(boost()) == 1
      assert MastodonStatus.context_key(note("public")) == 1
    end
  end
end
