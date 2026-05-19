# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Integration.NotificationsTest do
  @moduledoc """
  Exercises `SukhiFedi.Notifications` + the local-to-local write paths
  in `SukhiFedi.Notes` / `SukhiFedi.Social` that should emit rows.

      docker compose -f docker-compose.test.yml up -d
      MIX_ENV=test mix ecto.migrate
      mix test --only integration
  """

  use SukhiFedi.IntegrationCase, async: false

  @moduletag :integration

  alias SukhiFedi.{Notes, Notifications, Social}
  alias SukhiFedi.Schema.{Account, Note}

  describe "Social.request_follow/2 (local target)" do
    test "emits a `follow` notification for the followee" do
      alice = create_account!("alice_n_f")
      bob = create_account!("bob_n_f")

      {:ok, _} = Social.request_follow(alice, bob.id)

      [n] = Notifications.list(bob.id, [])
      assert n.type == "follow"
      assert n.from_account_id == alice.id
    end

    test "self-follow does not generate a notification (and is rejected)" do
      alice = create_account!("alice_self_n")
      assert {:error, :self_follow} = Social.request_follow(alice, alice.id)
      assert Notifications.list(alice.id, []) == []
    end
  end

  describe "Notes.favourite/2" do
    test "emits a `favourite` notification for the note author" do
      alice = create_account!("alice_fav")
      bob = create_account!("bob_fav")
      note = create_note!(alice.id, "hello")

      {:ok, _} = Notes.favourite(bob, note.id)

      [n] = Notifications.list(alice.id, [])
      assert n.type == "favourite"
      assert n.from_account_id == bob.id
      assert n.note_id == note.id
    end

    test "self-favourite does NOT notify (account_id == from_account_id)" do
      alice = create_account!("alice_selffav")
      note = create_note!(alice.id, "mine")
      {:ok, _} = Notes.favourite(alice, note.id)
      assert Notifications.list(alice.id, []) == []
    end
  end

  describe "Notes.reblog/2" do
    test "emits a `reblog` notification for the note author" do
      alice = create_account!("alice_reb")
      bob = create_account!("bob_reb")
      note = create_note!(alice.id, "boost me")

      {:ok, _} = Notes.reblog(bob, note.id)

      [n] = Notifications.list(alice.id, [])
      assert n.type == "reblog"
      assert n.from_account_id == bob.id
    end
  end

  describe "Notifications.list/2 filters" do
    test "types[] keeps only matching, exclude_types[] drops" do
      alice = create_account!("alice_filt")
      bob = create_account!("bob_filt")
      carol = create_account!("carol_filt")

      {:ok, _} = Social.request_follow(bob, alice.id)
      note = create_note!(alice.id, "x")
      {:ok, _} = Notes.favourite(carol, note.id)

      assert [%{type: "favourite"}] =
               Notifications.list(alice.id, types: ["favourite"])

      assert [%{type: "follow"}] =
               Notifications.list(alice.id, exclude_types: ["favourite"])

      assert length(Notifications.list(alice.id, [])) == 2
    end
  end

  describe "Notifications.dismiss/2 + clear/1" do
    test "dismiss flips dismissed_at; cleared rows disappear from list" do
      alice = create_account!("alice_dis")
      bob = create_account!("bob_dis")
      {:ok, _} = Social.request_follow(bob, alice.id)

      [n] = Notifications.list(alice.id, [])
      assert :ok = Notifications.dismiss(alice.id, n.id)
      assert Notifications.list(alice.id, []) == []
    end

    test "clear/1 bulk-dismisses every row" do
      alice = create_account!("alice_clr")
      bob = create_account!("bob_clr")
      carol = create_account!("carol_clr")

      {:ok, _} = Social.request_follow(bob, alice.id)
      {:ok, _} = Social.request_follow(carol, alice.id)
      assert length(Notifications.list(alice.id, [])) == 2

      assert :ok = Notifications.clear(alice.id)
      assert Notifications.list(alice.id, []) == []
    end
  end

  defp create_account!(username) do
    %Account{username: username, display_name: username, summary: ""}
    |> Repo.insert!()
  end

  defp create_note!(account_id, content) do
    %Note{
      account_id: account_id,
      content: content,
      visibility: "public"
    }
    |> Repo.insert!()
  end
end
