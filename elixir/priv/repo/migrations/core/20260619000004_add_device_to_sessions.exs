# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddDeviceToSessions do
  use Ecto.Migration

  # A coarse fingerprint of the device behind each session, so the
  # signed-in security page can list "where am I logged in" and a
  # never-before-seen device can trigger one quiet heads-up email. All
  # three are nullable: pre-existing sessions have no fingerprint, and a
  # session minted outside a request (none today) would have none either.
  def change do
    alter table(:sessions) do
      add :ip_text, :text
      add :user_agent, :text
      add :last_seen_at, :utc_datetime
    end
  end
end
