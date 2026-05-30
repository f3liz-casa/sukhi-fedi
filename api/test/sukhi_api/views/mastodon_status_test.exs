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
end
