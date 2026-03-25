# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Schema.Bookmark do
  use Ecto.Schema

  schema "bookmarks" do
    belongs_to :account, SukhiFedi.Schema.Account
    belongs_to :note, SukhiFedi.Schema.Note
    timestamps()
  end
end
