# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddLocalAuthToAccounts do
  use Ecto.Migration

  @moduledoc """
  Adds the two columns local accounts need to live: `email` and
  `password_hash`. Both nullable — remote accounts (`domain IS NOT
  NULL`) never get them, and existing local rows created via the admin
  back door pre-date this column. Application-level `changeset_local/2`
  requires them when registering through `POST /api/v1/accounts`.

  No unique index on email yet; signup uses `username` as the
  uniqueness key, and a future change will add `email` uniqueness once
  the field is mandatory.
  """

  def change do
    alter table(:accounts) do
      add :email, :string
      add :password_hash, :string
    end
  end
end
