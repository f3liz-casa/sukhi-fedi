# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.AP.Instructions.Boosts do
  @moduledoc """
  Inbound `Announce`: the reblog notification for a local note, the
  boost materialisation that puts a followed booster's pick on the home
  feed, and `Undo(Announce)`.
  """

  import Ecto.Query

  alias SukhiFedi.AP.Instructions.{Extract, Resolve}
  alias SukhiFedi.AP.Published
  alias SukhiFedi.Federation.NoteFetcher
  alias SukhiFedi.{Notifications, Repo}
  alias SukhiFedi.Schema.{Account, Boost, Follow, Note}

  @doc "Inbound `Announce` of a local note → reblog notification."
  def maybe_notify_announce(%{
        "type" => "Announce",
        "actor" => actor_uri,
        "object" => object_uri
      }) do
    with %Note{id: note_id, account_id: recipient_id} <- Resolve.resolve_target_note(object_uri),
         {:ok, %Account{id: from_id}} <- Resolve.resolve_or_ingest_actor(actor_uri) do
      Notifications.create(%{
        account_id: recipient_id,
        from_account_id: from_id,
        note_id: note_id,
        type: "reblog"
      })
    end

    :ok
  end

  def maybe_notify_announce(_), do: :ok

  @doc """
  Inbound `Announce` → materialise a `boosts` row so the home feed
  surfaces it as a reblog (the boost wrapper join in `Timelines`). We do
  this only when a local user actually follows the booster: a boost is
  how an un-followed author's post reaches the timeline, but a relay can
  forward Announces from anyone, and fetching every boosted note would be
  a fetch storm for rows nobody would ever see. When the booster is
  followed and we don't have the boosted note yet, fetch it (which also
  mirrors its media) so the join has something to render.

  Public + returns a status atom so the archive backfill can replay
  Announces. Idempotent (the boost row is unique per booster+note).
  """
  @spec materialize_boost(map()) :: :created | :not_followed | :unresolved | :skip
  def materialize_boost(%{"type" => "Announce", "actor" => actor_uri, "object" => object} = activity) do
    with uri when is_binary(uri) <- Extract.extract_object_id(object),
         {:ok, %Account{id: booster_id}} <- Resolve.resolve_or_ingest_actor(actor_uri),
         true <- followed_locally?(booster_id),
         {:ok, %Note{id: note_id}} <- resolve_or_fetch_note(uri) do
      # `created_at` orders the boost in the home feed (Timelines mints the
      # cursor from it), so stamp the Announce's `published` — not the
      # insert time, which would pile every back-filled boost onto "now".
      # `:replace` lets a re-run of the backfill correct an earlier row.
      %Boost{}
      |> Boost.changeset(%{account_id: booster_id, note_id: note_id})
      |> Published.stamp(activity)
      |> Repo.insert(on_conflict: {:replace, [:created_at]}, conflict_target: [:account_id, :note_id])
      |> case do
        # `:replace` returns the row (id set) whether inserted or refreshed,
        # so we can't tell new from updated here — both count as materialised.
        {:ok, %Boost{}} -> :created
        {:error, _} -> :unresolved
      end
    else
      false -> :not_followed
      {:error, _} -> :unresolved
      _ -> :skip
    end
  end

  def materialize_boost(_), do: :skip

  @doc "Undo(Announce): drop the `boosts` row so an un-boost leaves the home feed."
  def undo_announce(actor_uri, inner) do
    with %Note{id: note_id} <- Resolve.resolve_target_note(inner["object"]),
         {:ok, %Account{id: booster_id}} <- Resolve.resolve_or_ingest_actor(actor_uri) do
      from(b in Boost, where: b.account_id == ^booster_id and b.note_id == ^note_id)
      |> Repo.delete_all()
    end

    :ok
  end

  # True when some local user follows `account_id` (the booster). The
  # follow row's `follower_uri` is the follower's actor URI; a local one
  # lives under our domain.
  defp followed_locally?(account_id) do
    pattern = "https://#{SukhiFedi.Config.domain!()}/%"

    Repo.exists?(
      from(f in Follow,
        where:
          f.followee_id == ^account_id and f.state == "accepted" and
            like(f.follower_uri, ^pattern)
      )
    )
  end

  # Local or already-mirrored note → use it. A remote note we don't have
  # yet → fetch + mirror. A local note that resolved to nothing is gone
  # (deleted), so don't try to fetch our own URL back.
  defp resolve_or_fetch_note(uri) do
    case Resolve.resolve_target_note(uri) do
      %Note{} = n ->
        {:ok, n}

      nil ->
        if String.contains?(uri, SukhiFedi.Config.domain!()),
          do: {:error, :local_note_gone},
          else: NoteFetcher.fetch_and_mirror(uri)
    end
  end
end
