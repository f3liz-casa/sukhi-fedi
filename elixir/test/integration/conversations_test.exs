# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Integration.ConversationsTest do
  use SukhiFedi.IntegrationCase, async: false

  @moduletag :integration

  alias SukhiFedi.Conversations
  alias SukhiFedi.Schema.{Account, ConversationParticipant, Note}

  describe "list/2" do
    test "returns the latest DM note per conversation, excluding the viewer from accounts" do
      alice = create_account!("alice_conv")
      bob = create_account!("bob_conv")
      carol = create_account!("carol_conv")

      # Alice <-> Bob conversation
      cid_ab = "https://example.test/contexts/ab"
      add_participant!(cid_ab, alice.id)
      add_participant!(cid_ab, bob.id)
      _n1 = insert_note!(alice.id, "hi bob", cid_ab)
      n2 = insert_note!(bob.id, "hey alice", cid_ab)

      # Alice + Carol conversation
      cid_ac = "https://example.test/contexts/ac"
      add_participant!(cid_ac, alice.id)
      add_participant!(cid_ac, carol.id)
      n3 = insert_note!(carol.id, "hello!", cid_ac)

      result = Conversations.list(alice.id)
      assert length(result) == 2

      ids_in_order = Enum.map(result, & &1.id)
      # Newest note's conversation comes first (n3 was inserted after n2 → carol).
      assert hd(ids_in_order) == cid_ac
      assert Enum.at(ids_in_order, 1) == cid_ab

      ab = Enum.find(result, &(&1.id == cid_ab))
      assert ab.last_status.id == n2.id
      # Alice is the viewer — she should NOT be in the accounts list.
      assert [%{id: bob_id}] = ab.accounts
      assert bob_id == bob.id

      ac = Enum.find(result, &(&1.id == cid_ac))
      assert ac.last_status.id == n3.id
      assert [%{id: carol_id}] = ac.accounts
      assert carol_id == carol.id
    end

    test "empty when the viewer participates in nothing" do
      alice = create_account!("alice_empty_conv")
      assert Conversations.list(alice.id) == []
    end
  end

  defp create_account!(username) do
    %Account{username: username, display_name: username, summary: ""}
    |> Repo.insert!()
  end

  defp add_participant!(cid, account_id) do
    %ConversationParticipant{}
    |> ConversationParticipant.changeset(%{
      conversation_ap_id: cid,
      account_id: account_id
    })
    |> Repo.insert!()
  end

  defp insert_note!(account_id, content, conversation_ap_id) do
    %Note{
      account_id: account_id,
      content: content,
      visibility: "direct",
      conversation_ap_id: conversation_ap_id
    }
    |> Repo.insert!()
  end
end
