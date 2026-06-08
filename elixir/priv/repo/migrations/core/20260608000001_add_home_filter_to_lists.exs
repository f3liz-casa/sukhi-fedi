# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddHomeFilterToLists do
  use Ecto.Migration

  @moduledoc """
  Per-list home filters. A *non-exclusive* list can carry display
  filters that apply to its members' posts in the **home timeline**:
  show only posts with media, hide boosts, hide sensitive/CW. Exclusive
  lists drop their members from home entirely, so these are ignored
  there (see `SukhiFedi.Timelines.home/2`).
  """

  def change do
    alter table(:lists) do
      add :filter_only_media, :boolean, default: false, null: false
      add :filter_hide_boosts, :boolean, default: false, null: false
      add :filter_hide_sensitive, :boolean, default: false, null: false
    end
  end
end
