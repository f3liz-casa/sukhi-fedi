# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.Bookmark do
  use Ecto.Schema

  schema "bookmarks" do
    belongs_to :account, SukhiFedi.Schema.Account
    belongs_to :note, SukhiFedi.Schema.Note
    timestamps()
  end
end
