# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Delivery.FollowersSync do
  @moduledoc """
  FEP-8fcf: Followers Collection Synchronization.

  Provides helpers for computing the Collection-Synchronization header that
  accompanies shared-inbox deliveries, and for reconciling stale local follow
  records when we receive the header from a remote server.
  """

  import Ecto.Query
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Follow, Account}

  @public_ns "https://www.w3.org/ns/activitystreams#Public"

  @doc """
  Compute a SHA-256 digest (lowercase hex) of the sorted follower URIs for a
  local actor's followers collection.
  """
  def compute_digest(actor_uri) do
    username = username_from_uri(actor_uri)
    account = Repo.get_by(Account, username: username)

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
  Parse the Collection-Synchronization header value from an inbound request.
  Returns {:ok, %{collection_id, url, digest}} or :error.
  """
  def parse_header(nil), do: :error

  def parse_header(value) when is_binary(value) do
    # Format: collectionId="<uri>", url="<uri>", digest="<hex>"
    with [_, collection_id] <- Regex.run(~r/collectionId="([^"]+)"/, value),
         [_, url] <- Regex.run(~r/url="([^"]+)"/, value),
         [_, digest] <- Regex.run(~r/digest="([^"]+)"/, value) do
      {:ok, %{collection_id: collection_id, url: url, digest: digest}}
    else
      _ -> :error
    end
  end

  @doc """
  Reconcile local follow records for a remote actor whose followers collection
  digest we received. Removes stale follows not present in the remote collection.
  """
  def reconcile(sender_actor_uri, collection_items) when is_list(collection_items) do
    domain = Application.get_env(:sukhi_fedi, :domain)

    # Only process follows to local accounts
    local_follows =
      from(f in Follow,
        where: f.follower_uri == ^sender_actor_uri
      )
      |> Repo.all()

    Enum.each(local_follows, fn follow ->
      # If the followee is local and the sender is no longer in their followers
      # list according to the digest, remove the follow
      followee_uri = "https://#{domain}/users/#{follow_followee_username(follow)}"

      unless followee_uri in collection_items do
        Repo.delete(follow)
      end
    end)
  end

  defp follow_followee_username(follow) do
    account = Repo.get(Account, follow.followee_id)
    if account, do: account.username, else: nil
  end

  defp username_from_uri(uri) do
    uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()
  end
end
