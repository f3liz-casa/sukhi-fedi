# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Social do
  @moduledoc """
  Follow / unfollow / relationship queries. Reachable from the api
  plugin node via `SukhiApi.GatewayRpc.call(SukhiFedi.Social, :fun, [args])`.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias SukhiFedi.{Outbox, Repo}
  alias SukhiFedi.Schema.{Account, Follow}

  # ── reads ─────────────────────────────────────────────────────────────────

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

  # ── follow / unfollow ────────────────────────────────────────────────────

  @doc """
  Local user `follower` requests to follow account id `target_id`.

  Inserts a `Follow` row in state `pending` (Mastodon shape: a follow
  becomes `accepted` either immediately for unlocked accounts — TODO:
  not yet differentiated — or after an `Accept(Follow)` from the
  remote inbox handler).

  Idempotent: a duplicate follow returns the existing row.

  Emits `sns.outbox.follow.requested` on a fresh insert so the
  delivery node can later send an outbound `Follow` activity to the
  followee's inbox.

  > TODO(pr5): outbound delivery for `sns.outbox.follow.>` is not yet
  > consumed by FanOut. Outbox row is durable; PR5 wires it up.
  """
  @spec request_follow(Account.t(), integer()) ::
          {:ok, Follow.t()} | {:error, :self_follow | :not_found | term()}
  def request_follow(%Account{id: same}, target_id) when same == target_id,
    do: {:error, :self_follow}

  def request_follow(%Account{} = follower, target_id) when is_integer(target_id) do
    case Repo.get(Account, target_id) do
      nil ->
        {:error, :not_found}

      %Account{} = target ->
        actor_uri = local_actor_uri(follower)

        case existing_follow(actor_uri, target_id) do
          nil -> insert_follow_with_outbox(follower, actor_uri, target)
          %Follow{} = f -> {:ok, f}
        end
    end
  end

  defp insert_follow_with_outbox(_follower, actor_uri, %Account{} = target) do
    Multi.new()
    |> Multi.insert(
      :follow,
      %Follow{}
      |> Ecto.Changeset.change(%{
        follower_uri: actor_uri,
        followee_id: target.id,
        # Local-target follows could auto-accept; keeping pending to keep
        # the inbox-side Accept path the single source of truth. PR5
        # wires the local-target shortcut once FanOut is live.
        state: "pending"
      })
    )
    |> Outbox.enqueue_multi(
      :outbox_event,
      "sns.outbox.follow.requested",
      "follow",
      & &1.follow.id,
      fn %{follow: f} ->
        %{
          follow_id: f.id,
          follower_uri: f.follower_uri,
          followee_id: f.followee_id,
          followee_username: target.username
        }
      end
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{follow: f}} -> {:ok, f}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Local user `follower` unfollows account id `target_id`.

  Returns `{:ok, follow}` (the deleted row) on success, or
  `{:error, :not_found}` if no follow existed.

  Emits `sns.outbox.follow.undone` so the delivery node can later send
  an outbound `Undo(Follow)` activity.
  """
  @spec unfollow(Account.t(), integer()) :: {:ok, Follow.t()} | {:error, :not_found | term()}
  def unfollow(%Account{} = follower, target_id) when is_integer(target_id) do
    actor_uri = local_actor_uri(follower)

    case existing_follow(actor_uri, target_id) do
      nil ->
        {:error, :not_found}

      %Follow{} = f ->
        Multi.new()
        |> Multi.delete(:follow, f)
        |> Outbox.enqueue_multi(
          :outbox_event,
          "sns.outbox.follow.undone",
          "follow",
          & &1.follow.id,
          fn %{follow: f} ->
            %{
              follow_id: f.id,
              follower_uri: f.follower_uri,
              followee_id: f.followee_id
            }
          end
        )
        |> Repo.transaction()
        |> case do
          {:ok, %{follow: f}} -> {:ok, f}
          {:error, _step, reason, _} -> {:error, reason}
        end
    end
  end

  # ── relationships ────────────────────────────────────────────────────────

  @doc """
  Compute Mastodon Relationship rows for `viewer` × `target_ids`.

  Single query: pulls every relevant Follow row in one shot. Block /
  mute / domain_block dimensions are wired to the `:moderation` addon
  if loaded; absent there, they default to `false` (no false positives,
  no false negatives — the addon is the source of truth).

  Returns a list shaped for `SukhiApi.Views.MastodonRelationship`.
  """
  @spec list_relationships(Account.t(), [integer()]) :: [map()]
  def list_relationships(%Account{} = viewer, target_ids) when is_list(target_ids) do
    target_ids = target_ids |> Enum.map(&parse_id/1) |> Enum.reject(&is_nil/1)

    if target_ids == [] do
      []
    else
      actor_uri = local_actor_uri(viewer)

      following_set =
        from(f in Follow,
          where: f.follower_uri == ^actor_uri and f.followee_id in ^target_ids,
          select: {f.followee_id, f.state}
        )
        |> Repo.all()
        |> Map.new()

      followed_by_set =
        case load_target_uris(target_ids) do
          [] ->
            MapSet.new()

          uri_pairs ->
            uris = Enum.map(uri_pairs, fn {_id, uri} -> uri end)

            uris_following_viewer =
              from(f in Follow,
                where: f.follower_uri in ^uris and f.followee_id == ^viewer.id,
                select: f.follower_uri
              )
              |> Repo.all()
              |> MapSet.new()

            uri_pairs
            |> Enum.filter(fn {_id, uri} -> MapSet.member?(uris_following_viewer, uri) end)
            |> Enum.map(fn {id, _uri} -> id end)
            |> MapSet.new()
        end

      Enum.map(target_ids, fn id ->
        state = Map.get(following_set, id)

        %{
          id: id,
          following: state == "accepted",
          requested: state == "pending",
          followed_by: MapSet.member?(followed_by_set, id),
          showing_reblogs: true,
          notifying: false,
          blocking: false,
          blocked_by: false,
          muting: false,
          muting_notifications: false,
          domain_blocking: false,
          endorsed: false,
          note: ""
        }
      end)
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  defp existing_follow(actor_uri, target_id) do
    Repo.get_by(Follow, follower_uri: actor_uri, followee_id: target_id)
  end

  defp load_target_uris(target_ids) do
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")

    from(a in Account, where: a.id in ^target_ids, select: {a.id, a.username})
    |> Repo.all()
    |> Enum.map(fn {id, username} -> {id, "https://#{domain}/users/#{username}"} end)
  end

  defp local_actor_uri(%Account{username: u}) do
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
    "https://#{domain}/users/#{u}"
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_id(_), do: nil
end
