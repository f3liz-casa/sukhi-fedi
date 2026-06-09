# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Integration.InviteCodesTest do
  use SukhiFedi.IntegrationCase, async: false

  @moduletag :integration

  alias SukhiFedi.InviteCodes
  alias SukhiFedi.Schema.Account

  defp account!(username),
    do: Repo.insert!(%Account{username: username, display_name: username, summary: ""})

  test "an invite code is single-use; a second consume fails (C6)" do
    issuer = account!("inv_issuer")
    c1 = account!("inv_consumer1")
    c2 = account!("inv_consumer2")

    {:ok, code} = InviteCodes.issue(issuer.id)

    assert {:ok, _} = InviteCodes.consume(code.code, c1.id)
    # The atomic conditional UPDATE (is_nil(consumed_at)) means a re-use —
    # including a concurrent one that read the row as unconsumed — affects
    # zero rows and is rejected.
    assert {:error, :already_used} = InviteCodes.consume(code.code, c2.id)
  end

  test "an unknown code is invalid" do
    c = account!("inv_consumer3")
    assert {:error, :invalid} = InviteCodes.consume("does-not-exist", c.id)
  end
end
