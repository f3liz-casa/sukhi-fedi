# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddRemotePollCounts do
  use Ecto.Migration

  @moduledoc """
  A remote poll (an inbound AP `Question`) carries its tallies in the
  activity itself — `oneOf[]/anyOf[].replies.totalItems` and
  `votersCount` — not as local `poll_votes` rows we could count. Cache
  those numbers on the poll so the same render path serves local and
  remote polls. Local polls keep counting `poll_votes`; these columns
  stay 0 for them.
  """

  def change do
    alter table(:poll_options) do
      add :votes_count, :integer, null: false, default: 0
    end

    alter table(:polls) do
      add :voters_count, :integer, null: false, default: 0
    end
  end
end
