# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Fedi.Inbox do
  @moduledoc """
  Turns a verified inbound activity into a small typed instruction
  (`fedify.inbox.v1`) — the classify step of the inbox's
  verify → classify → execute pipeline (CODE_STYLE §2).

  Follow gets the special shape: it needs an `Accept(Follow)` reply and
  the follower's inbox, which means resolving the remote actor (signed
  when we have a local keypair, for Secure-Mode peers). Every other
  known type passes through as `save`; the executor
  (`AP.Instructions`) works on the activity JSON as delivered.

  The Bun version round-tripped activities through fedify's vocab
  classes here. For Mastodon-family senders that round trip is the
  identity transform (they already deliver compacted AS JSON), so the
  port hands the raw activity straight to the instruction and keeps
  classification to the one field it needs: `type`.
  """

  alias SukhiFedi.Fedi.Fetcher

  # Mirror of bun/fedify/activity_kinds.ts — Follow stays out of this
  # list because of its special reply shape.
  #
  # TODO(FEP-044f): hackers.pub and Hollo send `QuoteRequest` when one
  # of their users quotes a gated post, and expect a
  # `QuoteAuthorization` (or Reject) back — shaped like the Follow →
  # Accept flow below, so it belongs next to it. Until then their
  # quotes of our posts fall back to legacy handling.
  @generic_kinds ~w(Announce Create Update Delete Like EmojiReact Undo
                    Accept Reject Move Block Flag Add Remove)

  @type fetch_fun :: (String.t(), map() | nil -> {:ok, map()} | {:error, term()})

  @doc """
  Handles a `fedify.inbox.v1` payload and returns the instruction map
  (`action: save | save_and_reply | ignore`) the executor expects.
  """
  @spec handle(map(), fetch_fun()) :: {:ok, map()} | {:error, term()}
  def handle(payload, fetch_fun \\ &Fetcher.fetch_document/2)

  def handle(%{"raw" => raw} = payload, fetch_fun) when is_map(raw) do
    case raw["type"] do
      "Follow" -> follow_instruction(raw, payload, fetch_fun)
      kind when kind in @generic_kinds -> {:ok, %{"action" => "save", "object" => raw}}
      _ -> {:ok, %{"action" => "ignore"}}
    end
  end

  def handle(_payload, _fetch_fun), do: {:ok, %{"action" => "ignore"}}

  # The follower is waiting on the Accept — without it their
  # pending-follow state never resolves. Resolve their actor document
  # for the inbox URL, then hand back follow + reply + destination.
  defp follow_instruction(raw, payload, fetch_fun) do
    actor_uri = reference_uri(raw["actor"])
    followee_uri = reference_uri(raw["object"])

    with true <- is_binary(actor_uri) and is_binary(followee_uri),
         {:ok, %{"document" => actor}} <- fetch_fun.(actor_uri, payload["signAs"]),
         inbox when is_binary(inbox) <- actor["inbox"] do
      accept = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => accept_id(payload["selfDomain"] || URI.parse(followee_uri).host),
        "type" => "Accept",
        "actor" => followee_uri,
        "object" => %{
          "id" => raw["id"],
          "type" => "Follow",
          "actor" => actor_uri,
          "object" => followee_uri
        }
      }

      {:ok,
       %{
         "action" => "save_and_reply",
         "save" => %{"follow" => raw, "followeeUri" => followee_uri},
         "reply" => accept,
         "inbox" => inbox
       }}
    else
      # Missing ids or an unresolvable actor: same as the Bun handler,
      # ignore rather than fail the whole inbox POST.
      _ -> {:ok, %{"action" => "ignore"}}
    end
  end

  defp accept_id(domain) do
    "https://#{domain}/activities/accept/#{Ecto.UUID.generate()}"
  end

  # AP object references arrive as a bare IRI or an embedded object.
  defp reference_uri(uri) when is_binary(uri) and uri != "", do: uri
  defp reference_uri(%{"id" => uri}) when is_binary(uri) and uri != "", do: uri
  defp reference_uri(_), do: nil
end
