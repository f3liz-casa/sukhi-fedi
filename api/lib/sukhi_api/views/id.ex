# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Views.Id do
  @moduledoc """
  Mastodon serializes ids as opaque strings. We use bigserial integers
  internally and emit them as their decimal string. Wrapping the cast
  in this single function lets a future snowflake migration land as a
  one-line change here.
  """

  @spec encode(integer() | binary() | nil) :: String.t() | nil
  def encode(nil), do: nil
  def encode(n) when is_integer(n), do: Integer.to_string(n)
  def encode(s) when is_binary(s), do: s
end
