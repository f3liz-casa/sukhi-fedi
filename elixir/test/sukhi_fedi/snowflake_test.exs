# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.SnowflakeTest do
  use ExUnit.Case, async: true

  alias SukhiFedi.Snowflake

  describe "encode/2 ↔ to_unix_ms/1" do
    test "round-trips the millisecond instant" do
      ms = 1_710_000_000_000
      assert Snowflake.to_unix_ms(Snowflake.encode(ms, 0)) == ms
    end

    test "the counter lives in the low 16 bits and never disturbs the time" do
      ms = 1_710_000_000_000
      assert Snowflake.to_unix_ms(Snowflake.encode(ms, 65_535)) == ms
      # the counter masks to 16 bits, so 65_536 wraps back to 0
      assert Snowflake.encode(ms, 65_536) == Snowflake.encode(ms, 0)
    end

    test "the epoch maps to id 0 at counter 0" do
      assert Snowflake.encode(Snowflake.epoch_ms(), 0) == 0
      assert Snowflake.to_unix_ms(0) == Snowflake.epoch_ms()
    end
  end

  describe "time-sortability (the property minting-from-authored-time relies on)" do
    test "a later instant always mints a larger id, even past a maxed-out counter" do
      earlier = Snowflake.encode(1_710_000_000_000, 65_535)
      later = Snowflake.encode(1_710_000_000_001, 0)
      assert later > earlier
    end

    test "within the same millisecond, a higher counter sorts later" do
      ms = 1_710_000_000_000
      assert Snowflake.encode(ms, 7) > Snowflake.encode(ms, 3)
    end
  end

  describe "to_datetime/1" do
    test "decodes an id back to the instant it was built from" do
      dt = ~U[2024-06-01 12:00:00.000Z]
      ms = DateTime.to_unix(dt, :millisecond)
      assert Snowflake.to_datetime(Snowflake.encode(ms, 0)) == dt
    end
  end
end
