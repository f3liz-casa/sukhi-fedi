# SPDX-License-Identifier: MPL-2.0
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
