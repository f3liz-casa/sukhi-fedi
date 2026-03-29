# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Social do
  import Ecto.Query
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Follow

  def follow(follower_uri, followee_id) do
    %Follow{}
    |> Ecto.Changeset.change(%{
      follower_uri: follower_uri,
      followee_id: followee_id,
      state: "accepted"
    })
    |> Repo.insert(on_conflict: :nothing)
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
end
