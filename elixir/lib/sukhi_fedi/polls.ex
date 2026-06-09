# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Polls do
  @moduledoc """
  Poll reads + vote writes.

  Polls are owned by a Note (1:1). Each Poll has `options` (ordered)
  and `votes` (joined to an option). `multiple == false` constrains
  the caller to one option per vote.

  `vote/3` is idempotent on (account_id, poll_id, option_id). On the
  first insert for a multi-option poll it inserts all chosen options;
  for single-choice polls callers must pass exactly one option index.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Poll, PollOption, PollVote}

  @spec get_with_results(integer() | String.t(), integer() | nil) ::
          {:ok, map()} | {:error, :not_found}
  def get_with_results(poll_id, viewer_id \\ nil) do
    case SukhiFedi.Coercion.parse_id(poll_id) do
      nil ->
        {:error, :not_found}

      pid ->
        # A poll inherits its owning note's visibility — reading a
        # followers-only / direct poll's options and tallies is the same
        # disclosure as reading the note.
        case Repo.get(Poll, pid) do
          nil ->
            {:error, :not_found}

          %Poll{} = poll ->
            poll = Repo.preload(poll, :note)

            if is_nil(poll.note) or SukhiFedi.Notes.visible_to?(poll.note, viewer_id),
              do: {:ok, results_for(poll, viewer_id)},
              else: {:error, :not_found}
        end
    end
  end

  defp results_for(%Poll{id: pid} = poll, viewer_id) do
    options =
      Repo.all(
        from o in PollOption,
          where: o.poll_id == ^pid,
          order_by: [asc: o.position]
      )

    voted_option_ids =
      if is_integer(viewer_id), do: voted_options(pid, viewer_id), else: []

    voters_count =
      Repo.aggregate(
        from(v in PollVote, where: v.poll_id == ^pid, select: v.account_id),
        :count,
        :account_id,
        distinct: true
      )

    %{
      poll: poll,
      options: options,
      tallies: tally_for_poll(pid),
      voters_count: voters_count,
      voted_option_ids: voted_option_ids,
      voted?: voted_option_ids != []
    }
  end

  @spec vote(integer(), integer() | String.t(), [integer() | String.t()]) ::
          :ok | {:error, :not_found | :expired | :too_many_choices}
  def vote(account_id, poll_id, choices) when is_integer(account_id) do
    with pid when not is_nil(pid) <- SukhiFedi.Coercion.parse_id(poll_id),
         %Poll{} = poll <- Repo.get(Poll, pid),
         :ok <- check_poll_visible(poll, account_id),
         :ok <- check_not_expired(poll),
         option_ids when is_list(option_ids) <- normalize_choices(poll, choices) do
      # Single-choice polls replace the prior ballot (Mastodon UX) instead
      # of accumulating — otherwise N requests with different choices stuff
      # N votes from one account.
      base =
        if poll.multiple do
          Multi.new()
        else
          Multi.delete_all(
            Multi.new(),
            :clear,
            from(v in PollVote, where: v.poll_id == ^pid and v.account_id == ^account_id)
          )
        end

      multi =
        Enum.reduce(option_ids, base, fn opt_id, acc ->
          Multi.insert(
            acc,
            {:vote, opt_id},
            PollVote.changeset(%PollVote{}, %{
              account_id: account_id,
              poll_id: pid,
              option_id: opt_id
            }),
            on_conflict: :nothing,
            conflict_target: [:account_id, :poll_id, :option_id]
          )
        end)

      case Repo.transaction(multi) do
        {:ok, _} -> :ok
        {:error, _, _, _} -> :ok
      end
    else
      nil -> {:error, :not_found}
      :hidden -> {:error, :not_found}
      :expired -> {:error, :expired}
      :too_many -> {:error, :too_many_choices}
      _ -> {:error, :not_found}
    end
  end

  # ── helpers ────────────────────────────────────────────────────────────

  # A voter must be allowed to see the poll's owning note (same gate as
  # reading it), so a followers-only / direct poll can't be voted on by a
  # non-recipient who guessed the id.
  defp check_poll_visible(%Poll{} = poll, account_id) do
    note = Repo.preload(poll, :note).note

    if is_nil(note) or SukhiFedi.Notes.visible_to?(note, account_id),
      do: :ok,
      else: :hidden
  end

  defp tally_for_poll(poll_id) do
    Repo.all(
      from v in PollVote,
        where: v.poll_id == ^poll_id,
        group_by: v.option_id,
        select: {v.option_id, count(v.id)}
    )
    |> Map.new()
  end

  defp voted_options(poll_id, account_id) do
    Repo.all(
      from v in PollVote,
        where: v.poll_id == ^poll_id and v.account_id == ^account_id,
        select: v.option_id
    )
  end

  defp check_not_expired(%Poll{expires_at: nil}), do: :ok

  defp check_not_expired(%Poll{expires_at: exp}) do
    if DateTime.compare(exp, DateTime.utc_now()) == :gt, do: :ok, else: :expired
  end

  defp normalize_choices(%Poll{multiple: multiple, id: pid}, choices) do
    ids = choices |> List.wrap() |> Enum.map(&SukhiFedi.Coercion.parse_id/1) |> Enum.reject(&is_nil/1)

    cond do
      ids == [] -> []
      not multiple and length(ids) > 1 -> :too_many
      true -> filter_owned_options(pid, ids)
    end
  end

  # Treat indices (0..N-1) the way Mastodon clients send them, but
  # accept absolute PollOption ids for clients that already resolved
  # the row. Indices look up by ordered position; ids look up by PK.
  defp filter_owned_options(poll_id, ids) do
    options =
      Repo.all(
        from o in PollOption,
          where: o.poll_id == ^poll_id,
          order_by: [asc: o.position],
          select: %{id: o.id, position: o.position}
      )

    by_id = Map.new(options, fn %{id: id} = o -> {id, o} end)
    by_position = Map.new(options, fn %{position: pos} = o -> {pos, o} end)

    ids
    |> Enum.map(fn id ->
      case Map.get(by_id, id) || Map.get(by_position, id) do
        nil -> nil
        %{id: oid} -> oid
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end
end
