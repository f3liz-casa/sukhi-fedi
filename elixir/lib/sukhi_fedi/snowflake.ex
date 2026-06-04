# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Snowflake do
  @moduledoc """
  The Snowflake id layout shared across the system:

      id = ((unix_ms - epoch_ms) <<< 16) ||| (counter &&& 0xFFFF)

  A millisecond time component above a 2024 epoch, with a 16-bit
  per-millisecond counter in the low bits. The id is therefore
  *time-sortable*: a larger id means a later instant regardless of the
  counter — which is what lets a timeline interleave different id sources
  (note ids, synthesized boost cursors) by a plain numeric sort, and what
  makes minting an id from a post's authored time put it in the right
  chronological place.

  The same layout is minted in SQL by `snowflake_id()` (see the
  `SnowflakeNoteIds` migration). This module is the Elixir mirror used for
  the boost cursor and for decoding an id back to its instant. Keep the
  epoch and the 16-bit shift in step with the SQL function.
  """

  import Bitwise

  # 2024-01-01T00:00:00Z — matches `snowflake_id()` in Postgres.
  @epoch_ms 1_704_067_200_000

  @doc "The epoch (unix ms) the time component is measured from."
  @spec epoch_ms() :: integer()
  def epoch_ms, do: @epoch_ms

  @doc """
  Build an id from a unix-millisecond instant and a counter. The counter
  is masked to the low 16 bits, so the time component is never disturbed.
  """
  @spec encode(integer(), integer()) :: integer()
  def encode(unix_ms, counter) when is_integer(unix_ms) and is_integer(counter) do
    bsl(unix_ms - @epoch_ms, 16) ||| rem(counter, 65_536)
  end

  @doc "The unix-millisecond instant an id encodes."
  @spec to_unix_ms(integer()) :: integer()
  def to_unix_ms(id) when is_integer(id), do: bsr(id, 16) + @epoch_ms

  @doc "The `DateTime` (millisecond precision) an id encodes."
  @spec to_datetime(integer()) :: DateTime.t()
  def to_datetime(id) when is_integer(id), do: DateTime.from_unix!(to_unix_ms(id), :millisecond)
end
