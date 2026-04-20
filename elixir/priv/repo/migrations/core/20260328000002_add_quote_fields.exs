# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddQuoteFields do
  use Ecto.Migration

  def change do
    alter table(:notes) do
      add :quote_of_ap_id, :text
    end

    create index(:notes, [:quote_of_ap_id])
  end
end
