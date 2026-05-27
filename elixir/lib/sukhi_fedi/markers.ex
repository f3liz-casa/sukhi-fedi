# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Markers do
  @moduledoc """
  Per-account read-position markers backing Mastodon's `/api/v1/markers`.

  Two timelines are tracked: `"home"` and `"notifications"`. Each POST
  overwrites `last_read_id` and increments `version` — clients use the
  version for optimistic-concurrency, but in practice most just echo
  it back.
  """

  import Ecto.Query

  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Marker

  @allowed ~w(home notifications)

  @spec allowed?(any()) :: boolean()
  def allowed?(t) when is_binary(t), do: t in @allowed
  def allowed?(_), do: false

  @spec get(integer(), [String.t()]) :: %{String.t() => Marker.t()}
  def get(account_id, timelines)
      when is_integer(account_id) and is_list(timelines) do
    case Enum.filter(timelines, &allowed?/1) do
      [] ->
        %{}

      ts ->
        Repo.all(
          from m in Marker,
            where: m.account_id == ^account_id and m.timeline in ^ts
        )
        |> Map.new(&{&1.timeline, &1})
    end
  end

  @spec upsert(integer(), String.t(), String.t()) ::
          {:ok, Marker.t()} | {:error, Ecto.Changeset.t() | :invalid_timeline}
  def upsert(account_id, timeline, last_read_id)
      when is_integer(account_id) and is_binary(timeline) and is_binary(last_read_id) do
    if allowed?(timeline) do
      case Repo.get_by(Marker, account_id: account_id, timeline: timeline) do
        nil ->
          %Marker{}
          |> Marker.changeset(%{
            account_id: account_id,
            timeline: timeline,
            last_read_id: last_read_id,
            version: 1
          })
          |> Repo.insert()

        %Marker{} = existing ->
          existing
          |> Marker.changeset(%{
            last_read_id: last_read_id,
            version: existing.version + 1
          })
          |> Repo.update()
      end
    else
      {:error, :invalid_timeline}
    end
  end
end
