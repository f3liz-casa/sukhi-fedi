# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Articles do
  import Ecto.Query
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Article

  def create(attrs) do
    %Article{}
    |> Ecto.Changeset.cast(attrs, [:account_id, :ap_id, :title, :content, :summary, :published_at, :updated_at_ap])
    |> Ecto.Changeset.validate_required([:account_id, :ap_id, :title, :content])
    |> Repo.insert()
  end

  def get_by_ap_id(ap_id) do
    Repo.get_by(Article, ap_id: ap_id)
  end

  def list(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    from(a in Article,
      order_by: [desc: a.published_at],
      limit: ^limit,
      offset: ^offset,
      preload: [:account]
    )
    |> Repo.all()
  end

  def list_by_account(account_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    from(a in Article,
      where: a.account_id == ^account_id,
      order_by: [desc: a.published_at],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end
end
