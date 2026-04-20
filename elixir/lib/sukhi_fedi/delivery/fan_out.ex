# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Delivery.FanOut do
  @moduledoc """
  Resolves recipient inboxes and enqueues Oban delivery jobs.

  Work that is invariant across a single fan-out is computed here once —
  the raw JSON-LD body, the signing actor URI, and the FEP-8fcf
  `Collection-Synchronization` header — and threaded into every job via
  `args`. This turns N per-worker Postgres reads + N SHA-256 digests
  over the follower set into one of each, per fan-out.
  """

  alias SukhiFedi.Delivery.{Worker, FollowersSync}
  alias SukhiFedi.Schema.Object
  alias SukhiFedi.Relays

  @doc """
  Enqueues one delivery job per inbox URL for the given object.
  Relay inboxes (accepted subscriptions) are automatically included.
  """
  @spec enqueue(Object.t(), [String.t()]) :: :ok
  def enqueue(%Object{} = object, inbox_urls) when is_list(inbox_urls) do
    relay_inboxes = Relays.get_active_inbox_urls()
    all_inboxes = Enum.uniq(inbox_urls ++ relay_inboxes)

    actor_uri = object.actor_id
    raw_json = object.raw_json
    sync_header = FollowersSync.header_value(actor_uri)

    base_args = %{
      raw_json: raw_json,
      actor_uri: actor_uri,
      activity_id: object.ap_id,
      sync_header: sync_header
    }

    changesets =
      Enum.map(all_inboxes, fn inbox_url ->
        base_args
        |> Map.put(:inbox_url, inbox_url)
        |> Worker.new()
      end)

    Oban.insert_all(changesets)
    :ok
  end
end
