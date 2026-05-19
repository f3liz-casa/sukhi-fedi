# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Accounts do
  @moduledoc """
  Tiny read-only helper for the delivery node's local-account lookups.

  Delivery owns no write surface for accounts — local rows are produced
  by the gateway, remote shadows by the gateway's federation client.
  We just need a safe way to grab a *local* row by username; spelling
  `domain IS NULL` once here keeps every call site clean and avoids
  Ecto 3.12+'s "nil in get_by/2 keyword filter is unsafe" guard.
  """

  import Ecto.Query

  alias SukhiDelivery.Repo
  alias SukhiDelivery.Schema.Account

  @spec by_local_username(String.t() | nil) :: Account.t() | nil
  def by_local_username(nil), do: nil

  def by_local_username(username) when is_binary(username) do
    Repo.one(from a in Account, where: a.username == ^username and is_nil(a.domain), limit: 1)
  end
end
