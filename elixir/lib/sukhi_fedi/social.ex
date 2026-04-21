# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Social do
  import Ecto.Query
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Follow, Account}

  def list_followers(account_id, _opts \\ []) do
    from(f in Follow,
      where: f.followee_id == ^account_id and f.state == "accepted",
      select: f.follower_uri
    )
    |> Repo.all()
  end

  @doc """
  Returns a compact projection of the accounts the caller follows — one
  JOIN query, no N+1. Public-safe fields only (no key material).
  """
  def list_following(follower_uri, _opts \\ []) do
    from(f in Follow,
      join: a in Account,
      on: a.id == f.followee_id,
      where: f.follower_uri == ^follower_uri and f.state == "accepted",
      select: %{id: a.id, username: a.username, display_name: a.display_name, summary: a.summary}
    )
    |> Repo.all()
  end
end
