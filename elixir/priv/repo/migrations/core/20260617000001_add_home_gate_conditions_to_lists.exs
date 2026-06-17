# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddHomeGateConditionsToLists do
  use Ecto.Migration

  @moduledoc """
  More conditions for a list's home gate (see `SukhiFedi.Timelines.home/2`).

  A list already gates its members' posts in the home timeline: drop them
  entirely (`exclusive`) or narrow them (`filter_only_media` /
  `filter_hide_boosts` / `filter_hide_sensitive`). These add two more
  conditions a member's post must pass to reach home:

    * `filter_keyword` — admit only posts whose content or a tag matches
      this keyword (a leading `#` matches a hashtag). NULL/"" = no constraint.
    * `filter_replies` — how to treat the member's replies:
      `"all"` (no constraint), `"hide"` (drop replies), `"to_me"` (admit a
      reply only if it answers a post on this server).
  """

  def change do
    alter table(:lists) do
      add :filter_keyword, :string
      add :filter_replies, :string, default: "all", null: false
    end
  end
end
