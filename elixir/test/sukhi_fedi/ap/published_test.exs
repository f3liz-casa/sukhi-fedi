# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.AP.PublishedTest do
  use ExUnit.Case, async: true

  alias SukhiFedi.AP.Published
  alias SukhiFedi.Schema.Note

  describe "at/1" do
    test "parses an ISO8601 published into a second-precision DateTime" do
      assert Published.at(%{"published" => "2021-03-14T09:26:53Z"}) == ~U[2021-03-14 09:26:53Z]
    end

    test "truncates sub-second precision to the second" do
      assert Published.at(%{"published" => "2021-03-14T09:26:53.512Z"}) == ~U[2021-03-14 09:26:53Z]
    end

    test "an offset timestamp is normalised to UTC" do
      assert Published.at(%{"published" => "2021-03-14T18:26:53+09:00"}) == ~U[2021-03-14 09:26:53Z]
    end

    test "missing or unparseable published is nil" do
      assert Published.at(%{}) == nil
      assert Published.at(%{"published" => "not a date"}) == nil
      assert Published.at(%{"published" => nil}) == nil
    end
  end

  describe "stamp/2" do
    test "puts created_at when published parses" do
      cs = Published.stamp(Note.changeset(%Note{}, %{}), %{"published" => "2021-03-14T09:26:53Z"})
      assert Ecto.Changeset.get_change(cs, :created_at) == ~U[2021-03-14 09:26:53Z]
    end

    test "leaves the changeset untouched without a usable published" do
      cs = Published.stamp(Note.changeset(%Note{}, %{}), %{})
      assert Ecto.Changeset.get_change(cs, :created_at) == nil
    end
  end
end
