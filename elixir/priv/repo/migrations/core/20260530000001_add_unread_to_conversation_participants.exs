# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddUnreadToConversationParticipants do
  use Ecto.Migration

  # Per-participant unread flag. Mastodon's conversation `unread` is
  # per-account (the account_conversations row), which is exactly what a
  # conversation_participants row is here. A new DM marks the row unread
  # for every recipient; the sender's own row stays read; the
  # `POST /api/v1/conversations/:id/read` endpoint clears it.
  def change do
    alter table(:conversation_participants) do
      add :unread, :boolean, null: false, default: false
    end
  end
end
