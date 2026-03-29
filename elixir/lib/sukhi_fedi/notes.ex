# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Notes do
  import Ecto.Query
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Note

  def create_note(attrs) do
    %Note{}
    |> Note.changeset(attrs)
    |> Repo.insert()
  end

  def get_note(id) do
    Repo.get(Note, id)
  end

  def list_notes_by_account(account_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    
    from(n in Note,
      where: n.account_id == ^account_id,
      order_by: [desc: n.created_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  def list_public_notes(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    
    from(n in Note,
      where: n.visibility == "public",
      order_by: [desc: n.created_at],
      limit: ^limit
    )
    |> Repo.all()
  end
end
