# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Views.MastodonPollTest do
  use ExUnit.Case, async: true

  alias SukhiApi.Views.MastodonPoll

  defp ctx(voted_option_ids) do
    %{
      poll: %{id: 1, expires_at: nil, multiple: false},
      options: [%{id: 10, title: "a"}, %{id: 20, title: "b"}, %{id: 30, title: "c"}],
      tallies: %{10 => 1, 20 => 0, 30 => 2},
      voted?: voted_option_ids != [],
      voted_option_ids: voted_option_ids
    }
  end

  describe "own_votes is option indices, not DB ids (Mastodon spec)" do
    test "maps each voted option id to its position in the options list" do
      assert MastodonPoll.render(ctx([30])).own_votes == [2]
      assert MastodonPoll.render(ctx([10, 30])).own_votes == [0, 2]
    end

    test "no votes renders an empty list" do
      assert MastodonPoll.render(ctx([])).own_votes == []
    end

    test "an id not among the options is dropped" do
      assert MastodonPoll.render(ctx([10, 999])).own_votes == [0]
    end
  end

  test "nil poll renders nil" do
    assert MastodonPoll.render(nil) == nil
  end
end
