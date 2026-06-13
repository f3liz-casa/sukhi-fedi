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

  test "preview reports the issuer and leaves the code consumable" do
    issuer = account!("inv_previewer")
    {:ok, code} = InviteCodes.issue(issuer.id)

    assert {:ok, %{issuer_handle: "inv_previewer", issuer_display_name: "inv_previewer"}} =
             InviteCodes.preview(code.code)

    # preview は読むだけ ─ そのあと、まだ consume できる。
    consumer = account!("inv_preview_consumer")
    assert {:ok, _} = InviteCodes.consume(code.code, consumer.id)
  end

  test "preview rejects used, expired, and unknown codes" do
    issuer = account!("inv_preview_issuer2")
    consumer = account!("inv_preview_consumer2")

    {:ok, used} = InviteCodes.issue(issuer.id)
    {:ok, _} = InviteCodes.consume(used.code, consumer.id)
    assert {:error, :already_used} = InviteCodes.preview(used.code)

    past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
    {:ok, expired} = InviteCodes.issue(issuer.id, expires_at: past)
    assert {:error, :expired} = InviteCodes.preview(expired.code)

    assert {:error, :invalid} = InviteCodes.preview("does-not-exist")
  end
end
