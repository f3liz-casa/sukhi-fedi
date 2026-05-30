# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Coercion do
  @moduledoc """
  Small id-coercion helpers shared by the context modules. Mastodon API
  ids arrive as strings but our rows are keyed on integers, so the same
  two shapes kept recurring:

    * `parse_id/1` — lenient: a bad string becomes `nil` (the caller then
      404s rather than crashing). This is the right default for anything
      derived from request params.
    * `to_int!/1` — strict: a bad string raises. Use it only where the id
      is already known to be well-formed and a bad value is a bug.
  """

  @doc "Coerce an id to an integer, or `nil` when it isn't a parseable one."
  @spec parse_id(term()) :: integer() | nil
  def parse_id(id) when is_integer(id), do: id

  def parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  def parse_id(_), do: nil

  @doc "Coerce an integer or numeric string to an integer; raises otherwise."
  @spec to_int!(integer() | binary()) :: integer()
  def to_int!(v) when is_integer(v), do: v
  def to_int!(v) when is_binary(v), do: String.to_integer(v)
end
