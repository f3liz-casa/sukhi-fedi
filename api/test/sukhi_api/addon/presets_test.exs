# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Addon.PresetsTest do
  use ExUnit.Case, async: true

  alias SukhiApi.Addon.Presets

  test "mastodon_compatible expands to the documented Mastodon-shape addons" do
    ids = Presets.expand([:mastodon_compatible])

    assert :mastodon_api in ids
    assert :media in ids
    assert :moderation in ids
    assert :pinned_notes in ids
    assert :streaming in ids
    assert :web_push in ids

    # Retired addons (feeds, bookmarks, articles) must not leak back
    # in via a preset — Notes / Timelines / the Bookmarks columns on
    # Note are the canonical surface now.
    refute :feeds in ids
    refute :bookmarks in ids
    refute :articles in ids
    refute :misskey_api in ids
    refute :nodeinfo_monitor in ids
  end

  test "server_version_watcher bundles the watcher with its visibility surfaces" do
    ids = Presets.expand([:server_version_watcher])

    assert :nodeinfo_monitor in ids
    assert :pinned_notes in ids
    assert length(ids) == 2
  end

  test "expanding multiple presets unions overlapping ids" do
    ids = Presets.expand([:mastodon_compatible, :server_version_watcher])

    assert Enum.count(ids, &(&1 == :pinned_notes)) == 1
    assert :nodeinfo_monitor in ids
    assert :mastodon_api in ids
  end

  test "unknown preset ids contribute nothing" do
    assert Presets.expand([:bogus]) == []
  end

  test "gateway and api preset definitions stay in sync" do
    # Guards against drift between the duplicated maps.
    assert SukhiApi.Addon.Presets.all() == %{
             mastodon_compatible: [
               :mastodon_api,
               :media,
               :moderation,
               :pinned_notes,
               :streaming,
               :web_push
             ],
             server_version_watcher: [
               :nodeinfo_monitor,
               :pinned_notes
             ]
           }
  end
end
