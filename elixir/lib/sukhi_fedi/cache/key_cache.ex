# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Cache.KeyCache do
  @moduledoc """
  Public key cache backed by ETS. TTL: 1 hour.
  """

  alias SukhiFedi.Cache.Ets

  @ttl_seconds 3_600

  @doc "Get a cached public key by key_id."
  @spec get(String.t()) :: {:ok, String.t()} | :miss
  def get(key_id), do: Ets.get(:key_cache, key_id)

  @doc "Store a public key with a 1-hour TTL."
  @spec put(String.t(), String.t()) :: true
  def put(key_id, public_key), do: Ets.put(:key_cache, key_id, public_key, @ttl_seconds)

  @doc "Invalidate a cached public key."
  @spec delete(String.t()) :: true
  def delete(key_id), do: Ets.delete(:key_cache, key_id)
end
