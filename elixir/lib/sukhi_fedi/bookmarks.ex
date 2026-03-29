# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Bookmarks do
  import Ecto.Query
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Bookmark, Note}

  def create(account_id, note_id) do
    %Bookmark{account_id: account_id, note_id: note_id}
    |> Repo.insert(on_conflict: :nothing)
  end

  def delete(account_id, note_id) do
    Repo.delete_all(from b in Bookmark, where: b.account_id == ^account_id and b.note_id == ^note_id)
  end

  def list(account_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    from(b in Bookmark,
      where: b.account_id == ^account_id,
      order_by: [desc: b.inserted_at],
      limit: ^limit,
      offset: ^offset,
      join: n in Note, on: b.note_id == n.id,
      preload: [note: n]
    )
    |> Repo.all()
  end
end
