# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Accounts do
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Account

  def get_account_by_username(username) do
    Repo.get_by(Account, username: username)
  end
end
