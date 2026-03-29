# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Accounts do
  import Ecto.Query
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Account

  def create_account(attrs) do
    %Account{}
    |> Account.changeset(attrs)
    |> Repo.insert()
  end

  def get_account(id) do
    Repo.get(Account, id)
  end

  def get_account_by_username(username) do
    Repo.get_by(Account, username: username)
  end

  def update_profile(account, attrs) do
    account
    |> Account.profile_changeset(attrs)
    |> Repo.update()
  end
end
