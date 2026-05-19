# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Integration.ListsTest do
  use SukhiFedi.IntegrationCase, async: false

  @moduletag :integration

  alias SukhiFedi.{Lists, Notes, Social}
  alias SukhiFedi.Schema.{Account, Follow}

  describe "create/3 + list_for/1" do
    test "owner-scoped — alice's lists don't show in bob's index" do
      alice = create_account!("alice_lists")
      bob = create_account!("bob_lists")

      {:ok, list} = Lists.create(alice.id, %{title: "Friends"})
      assert list.title == "Friends"

      assert [%{id: lid, title: "Friends"}] = Lists.list_for(alice.id)
      assert lid == list.id
      assert Lists.list_for(bob.id) == []
    end
  end

  describe "membership" do
    test "only accepts members the owner already follows" do
      alice = create_account!("alice_mem")
      bob = create_account!("bob_mem")
      _carol = create_account!("carol_mem")

      {:ok, _} = Social.request_follow(alice, bob.id)
      # local follow lands as accepted automatically
      {:ok, list} = Lists.create(alice.id, %{title: "Inner circle"})

      # bob is followed → accepted into the list
      # carol is not followed → silently dropped
      assert :ok = Lists.add_accounts(alice.id, list.id, [bob.id, 99_999_999])
      assert {:ok, [%{id: m_id}]} = Lists.list_accounts(alice.id, list.id)
      assert m_id == bob.id
    end

    test "remove_accounts is idempotent" do
      alice = create_account!("alice_rm")
      bob = create_account!("bob_rm")
      {:ok, _} = Social.request_follow(alice, bob.id)
      {:ok, list} = Lists.create(alice.id, %{title: "x"})
      :ok = Lists.add_accounts(alice.id, list.id, [bob.id])

      assert :ok = Lists.remove_accounts(alice.id, list.id, [bob.id])
      assert :ok = Lists.remove_accounts(alice.id, list.id, [bob.id])
      assert {:ok, []} = Lists.list_accounts(alice.id, list.id)
    end
  end

  describe "timeline" do
    test "returns notes from list members only" do
      alice = create_account!("alice_tl_l")
      bob = create_account!("bob_tl_l")
      carol = create_account!("carol_tl_l")

      {:ok, _} = Social.request_follow(alice, bob.id)
      {:ok, list} = Lists.create(alice.id, %{title: "from-bob"})
      :ok = Lists.add_accounts(alice.id, list.id, [bob.id])

      # only bob's note should appear
      {:ok, _} = Notes.create_status(bob, %{"status" => "from bob"})
      {:ok, _} = Notes.create_status(carol, %{"status" => "from carol"})

      {:ok, notes} = Lists.timeline(alice.id, list.id)

      assert length(notes) == 1
      [%{account_id: aid}] = notes
      assert aid == bob.id
    end

    test "scope mismatch — viewer doesn't own the list → :not_found" do
      alice = create_account!("alice_scope")
      bob = create_account!("bob_scope")
      {:ok, list} = Lists.create(alice.id, %{title: "private"})

      assert {:error, :not_found} = Lists.timeline(bob.id, list.id)
      assert {:error, :not_found} = Lists.list_accounts(bob.id, list.id)
    end
  end

  defp create_account!(username) do
    %Account{username: username, display_name: username, summary: ""}
    |> Repo.insert!()
  end

  # Suppress unused alias warning — Follow is referenced for clarity
  # in the test moduledoc above but not strictly needed at runtime.
  _ = Follow
end
