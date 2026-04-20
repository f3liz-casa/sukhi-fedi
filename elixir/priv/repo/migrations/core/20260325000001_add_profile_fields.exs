# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddProfileFields do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :avatar_url, :text
      add :banner_url, :text
      add :bio, :text
    end
  end
end
