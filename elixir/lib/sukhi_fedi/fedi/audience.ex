# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Fedi.Audience do
  @moduledoc """
  Single source of truth for ActivityPub audience (`to`/`cc`).

  Port of `bun/fedify/addressing.ts`, which exists because two builders
  once shipped without addressing and receivers that gate visibility on
  it (iceshrimp, Mastodon) silently dropped the activities. Keep every
  builder routed through here so the next one can't repeat that.
  """

  @as_public "https://www.w3.org/ns/activitystreams#Public"

  @type resolved :: %{to: [String.t()], cc: [String.t()]}

  @spec as_public() :: String.t()
  def as_public, do: @as_public

  @spec public(String.t()) :: resolved()
  def public(actor), do: %{to: [@as_public], cc: [followers(actor)]}

  @spec unlisted(String.t()) :: resolved()
  def unlisted(actor), do: %{to: [followers(actor)], cc: [@as_public]}

  @spec followers_only(String.t()) :: resolved()
  def followers_only(actor), do: %{to: [followers(actor)], cc: []}

  @spec direct([String.t()]) :: resolved()
  def direct(actors), do: %{to: actors, cc: []}

  @doc """
  For Undo / Accept / Reject: address to the AP id of the thing being
  acted on. Routing is what matters; the delivery set is carried
  separately by `recipientInboxes`.
  """
  @spec mirror(String.t()) :: resolved()
  def mirror(inner_object_id), do: %{to: [inner_object_id], cc: []}

  defp followers(actor), do: actor <> "/followers"
end
