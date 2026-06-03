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
