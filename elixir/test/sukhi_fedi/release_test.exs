# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.ReleaseTest do
  use ExUnit.Case, async: true

  # DB-free assertions, but the app boots a Repo at test start, so this is
  # picked up by the `--only integration` runner (same as UrlGuardTest).
  @moduletag :integration

  alias SukhiFedi.Release

  # The fail-fast gate's pure core: given Ecto.Migrator.migrations/2's
  # `[{status, version, name}]`, which pending (`:down`) versions sit below
  # the highest applied (`:up`) one? Driving it directly needs no DB.
  describe "migrations_out_of_order/1" do
    test "clean: all applied, then all pending — nothing out of order" do
      migrations = [
        {:up, 1, "a"},
        {:up, 2, "b"},
        {:down, 3, "c"},
        {:down, 4, "d"}
      ]

      assert Release.migrations_out_of_order(migrations) == []
    end

    test "a pending migration below the highest applied is offending" do
      migrations = [
        {:up, 1, "a"},
        {:down, 2, "b"},
        {:up, 3, "c"}
      ]

      assert Release.migrations_out_of_order(migrations) == [2]
    end

    test "lists every offending version, not just the first" do
      migrations = [
        {:down, 1, "a"},
        {:up, 2, "b"},
        {:down, 3, "c"},
        {:up, 5, "e"}
      ]

      assert Release.migrations_out_of_order(migrations) == [1, 3]
    end

    test "fresh database (nothing applied yet) is never out of order" do
      migrations = [{:down, 1, "a"}, {:down, 2, "b"}]

      assert Release.migrations_out_of_order(migrations) == []
    end

    test "a pending migration above the highest applied is fine" do
      migrations = [{:up, 1, "a"}, {:up, 2, "b"}, {:down, 3, "c"}]

      assert Release.migrations_out_of_order(migrations) == []
    end
  end
end
