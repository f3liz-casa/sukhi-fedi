# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Delivery.FollowersSync do
  @moduledoc """
  FEP-8fcf: Followers Collection Synchronization.

  Computes the Collection-Synchronization header for outbound shared-inbox
  deliveries, and reconciles stale local follow records when we receive
  the header from a remote server. Header parsing lives on the gateway
  (InboxController) since it's a pure regex and the parsed result only
  drives the enqueue of a follow-up Oban job.
  """

  import Ecto.Query
  alias SukhiDelivery.Repo
  alias SukhiDelivery.Schema.{Follow, Account}

  @doc """
  Compute a SHA-256 digest (lowercase hex) of the sorted follower URIs for a
  local actor's followers collection.
  """
  def compute_digest(actor_uri) do
    username = username_from_uri(actor_uri)
    account = SukhiDelivery.Accounts.by_local_username(username)

    if account do
      follower_uris =
        from(f in Follow,
          where: f.followee_id == ^account.id and f.state == "accepted",
          select: f.follower_uri,
          order_by: f.follower_uri
        )
        |> Repo.all()

      :crypto.hash(:sha256, Enum.join(follower_uris, "\n"))
      |> Base.encode16(case: :lower)
    else
      nil
    end
  end

  @doc """
  Build the value for the Collection-Synchronization header for outbound
  shared-inbox deliveries by a local actor.
  """
  def header_value(actor_uri) do
    case compute_digest(actor_uri) do
      nil ->
        nil

      digest ->
        followers_uri = "#{actor_uri}/followers"
        digest_uri = "#{actor_uri}/followers#digest"
        ~s(collectionId="#{followers_uri}", url="#{digest_uri}", digest="#{digest}")
    end
  end

  @doc """
  Reconcile local follow records for a remote actor whose followers collection
  digest we received. Removes stale follows not present in the remote collection.
  """
  def reconcile(sender_actor_uri, collection_items) when is_list(collection_items) do
    domain = Application.get_env(:sukhi_delivery, :domain)
    local_prefix = "https://#{domain}/users/"

    # The sender is a remote actor; `collection_items` is the @our-domain
    # subset of *its* followers collection (the URIs of our local users it
    # believes follow it). We reconcile our local "local-user follows sender"
    # edges against that list. A local sender has no actor_uri row, so this
    # no-ops — we never touch a local actor's own follow edges.
    sender = Repo.one(from a in Account, where: a.actor_uri == ^sender_actor_uri, limit: 1)

    if sender do
      local_follows =
        from(f in Follow,
          where:
            f.followee_id == ^sender.id and f.state == "accepted" and
              like(f.follower_uri, ^(local_prefix <> "%")),
          select: %{id: f.id, follower_uri: f.follower_uri}
        )
        |> Repo.all()

      stale_ids =
        for %{id: id, follower_uri: uri} <- local_follows,
            uri not in collection_items,
            do: id

      unless stale_ids == [] do
        from(f in Follow, where: f.id in ^stale_ids) |> Repo.delete_all()
      end
    end

    :ok
  end

  defp username_from_uri(uri) do
    uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()
  end
end
