# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Social do
  import Ecto.Query
  alias SukhiFedi.{Repo, Outbox, Moderation}
  alias SukhiFedi.Schema.Follow

  @doc """
  Record a follow and enqueue `sns.outbox.follow.requested` atomically.

  A single Ecto.Multi transaction does the follows insert and the
  outbox row. The federation layer downstream decides whether the
  followee is local (no delivery needed) or remote (HTTP POST to inbox).
  """
  def follow(follower_uri, followee_id) do
    follow_changeset =
      Ecto.Changeset.change(%Follow{}, %{
        follower_uri: follower_uri,
        followee_id: followee_id,
        state: "accepted"
      })

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:follow, follow_changeset, on_conflict: :nothing, returning: true)
    |> Outbox.enqueue_multi(
      :outbox_event,
      "sns.outbox.follow.requested",
      "follow",
      fn %{follow: follow} -> "#{follow.follower_uri}->#{follow.followee_id}" end,
      fn %{follow: follow} ->
        %{
          follower_uri: follow.follower_uri,
          followee_id: follow.followee_id,
          state: follow.state
        }
      end
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{follow: follow}} -> {:ok, follow}
      {:error, :follow, changeset, _} -> {:error, changeset}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  def unfollow(follower_uri, followee_id) do
    from(f in Follow,
      where: f.follower_uri == ^follower_uri and f.followee_id == ^followee_id
    )
    |> Repo.delete_all()
    
    :ok
  end

  def following?(follower_uri, followee_id) do
    query = from f in Follow,
      where: f.follower_uri == ^follower_uri and f.followee_id == ^followee_id
    
    Repo.exists?(query)
  end

  def list_followers(account_id, _opts \\ []) do
    from(f in Follow,
      where: f.followee_id == ^account_id and f.state == "accepted",
      select: f.follower_uri
    )
    |> Repo.all()
  end

  def list_following(follower_uri, _opts \\ []) do
    from(f in Follow,
      where: f.follower_uri == ^follower_uri and f.state == "accepted",
      select: f.followee_id
    )
    |> Repo.all()
  end

  # Thin delegations to Moderation so callers can talk to a single
  # relationship-centric module. Moderation owns the actual mute/block
  # storage; Social is the read/write facade used from controllers.
  def mute(account_id, target_id), do: Moderation.mute(account_id, target_id)
  def unmute(account_id, target_id), do: Moderation.unmute(account_id, target_id)
  def muting?(account_id, target_id), do: Moderation.muted?(account_id, target_id)
  def block(account_id, target_id), do: Moderation.block(account_id, target_id)
  def unblock(account_id, target_id), do: Moderation.unblock(account_id, target_id)
  def blocking?(account_id, target_id), do: Moderation.blocked?(account_id, target_id)
end
