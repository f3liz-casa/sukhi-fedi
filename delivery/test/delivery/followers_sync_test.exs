# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Delivery.FollowersSyncTest do
  use ExUnit.Case, async: true

  alias SukhiDelivery.Delivery.FollowersSync

  describe "items_from_body/1 — only an inline list is authoritative" do
    test "reads an inline `items` list" do
      assert {:ok, ["a", "b"]} = FollowersSync.items_from_body(%{"items" => ["a", "b"]})
    end

    test "reads an inline `orderedItems` list" do
      assert {:ok, ["x"]} = FollowersSync.items_from_body(%{"orderedItems" => ["x"]})
    end

    test "an inline empty list is authoritative (genuinely zero)" do
      assert {:ok, []} = FollowersSync.items_from_body(%{"orderedItems" => []})
    end

    test "a paginated collection (no inline items, members under first/next) is NOT zero" do
      paginated = %{
        "type" => "OrderedCollection",
        "totalItems" => 1200,
        "first" => "https://remote.example/users/x/followers?page=1"
      }

      assert {:error, :no_inline_items} = FollowersSync.items_from_body(paginated)
    end

    test "a body with no items key at all is not coerced to empty" do
      assert {:error, :no_inline_items} = FollowersSync.items_from_body(%{"type" => "OrderedCollection"})
    end
  end

  describe "reconcile/2 — never delete on an unauthoritative result" do
    test "an empty list is a no-op (no deletion), even with local follows present" do
      # The empty case is ambiguous (genuinely-zero vs could-not-enumerate); we
      # refuse to delete because pruning a real follow edge is irreversible.
      # Returns :ok before touching the DB, so this is a pure guard test.
      assert FollowersSync.reconcile("https://remote.example/users/x", []) == :ok
    end
  end
end
