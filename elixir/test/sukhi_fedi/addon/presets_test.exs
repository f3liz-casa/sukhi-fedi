# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addon.PresetsTest do
  use ExUnit.Case, async: true

  alias SukhiFedi.Addon.Presets

  test "mastodon_compatible expands to the documented Mastodon-shape addons" do
    ids = Presets.expand([:mastodon_compatible])

    assert :mastodon_api in ids
    assert :media in ids
    assert :feeds in ids
    assert :moderation in ids
    assert :bookmarks in ids
    assert :pinned_notes in ids
    assert :streaming in ids
    assert :web_push in ids

    refute :articles in ids
    refute :misskey_api in ids
    refute :nodeinfo_monitor in ids
  end

  test "server_version_watcher bundles the watcher with its visibility surfaces" do
    ids = Presets.expand([:server_version_watcher])

    assert :nodeinfo_monitor in ids
    assert :feeds in ids
    assert :pinned_notes in ids
    assert length(ids) == 3
  end

  test "expanding multiple presets unions overlapping ids" do
    ids = Presets.expand([:mastodon_compatible, :server_version_watcher])

    # feeds and pinned_notes overlap; each must appear exactly once
    assert Enum.count(ids, &(&1 == :feeds)) == 1
    assert Enum.count(ids, &(&1 == :pinned_notes)) == 1
    assert :nodeinfo_monitor in ids
    assert :mastodon_api in ids
  end

  test "unknown preset ids contribute nothing" do
    assert Presets.expand([:bogus]) == []
    assert Presets.expand([:bogus, :server_version_watcher]) |> Enum.sort() ==
             Presets.expand([:server_version_watcher]) |> Enum.sort()
  end

  test "empty list expands to empty list" do
    assert Presets.expand([]) == []
  end
end
