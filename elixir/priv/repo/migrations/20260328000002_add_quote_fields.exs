# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Repo.Migrations.AddQuoteFields do
  use Ecto.Migration

  def change do
    alter table(:notes) do
      add :quote_of_ap_id, :text
    end

    create index(:notes, [:quote_of_ap_id])
  end
end
