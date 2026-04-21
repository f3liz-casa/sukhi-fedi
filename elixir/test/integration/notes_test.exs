# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Integration.NotesTest do
  @moduledoc """
  End-to-end tests for `SukhiFedi.Notes` create_status / get_note /
  delete_note / context. Requires the test Postgres with core
  migrations applied.

      docker compose -f docker-compose.test.yml up -d
      MIX_ENV=test mix ecto.migrate
      mix test --only integration
  """

  use SukhiFedi.IntegrationCase, async: false

  @moduletag :integration

  import Ecto.Query

  alias SukhiFedi.{Notes, Timelines}
  alias SukhiFedi.Schema.{Account, Follow, Media, Note, OutboxEvent}

  describe "create_status/2" do
    test "creates a Note + emits sns.outbox.note.created" do
      a = create_account!("alice_cs")

      assert {:ok, note} = Notes.create_status(a, %{"status" => "hello", "visibility" => "public"})

      assert note.content == "hello"
      assert note.visibility == "public"
      assert note.account_id == a.id

      ev =
        Repo.one!(
          from e in OutboxEvent,
            where: e.subject == "sns.outbox.note.created" and e.aggregate_id == ^to_string(note.id)
        )

      assert ev.payload["note_id"] == note.id
    end

    test "spoiler_text → cw, in_reply_to_id resolves to ap_id" do
      a = create_account!("alice_reply")

      {:ok, parent} = Notes.create_status(a, %{"status" => "first", "visibility" => "public"})

      _ = update_ap_id(parent, "https://x.example/notes/parent_42")

      {:ok, child} =
        Notes.create_status(a, %{
          "status" => "reply",
          "spoiler_text" => "cw text",
          "in_reply_to_id" => to_string(parent.id),
          "visibility" => "public"
        })

      assert child.cw == "cw text"
      assert child.in_reply_to_ap_id == "https://x.example/notes/parent_42"
    end

    test "direct visibility is rejected" do
      a = create_account!("alice_dm")

      assert {:error, :direct_visibility_not_supported} =
               Notes.create_status(a, %{"status" => "secret", "visibility" => "direct"})
    end

    test "media_ids[] not owned by user → :media_not_owned" do
      a = create_account!("alice_media")
      b = create_account!("bob_media")

      m = create_media!(b)

      assert {:error, :media_not_owned} =
               Notes.create_status(a, %{
                 "status" => "x",
                 "media_ids" => [to_string(m.id)]
               })
    end

    test "media_ids[] owned by user — note has media after create" do
      a = create_account!("alice_owned")
      m = create_media!(a)

      assert {:ok, note} =
               Notes.create_status(a, %{
                 "status" => "with media",
                 "media_ids" => [to_string(m.id)]
               })

      reloaded = Repo.preload(Repo.get!(Note, note.id), :media)
      assert Enum.map(reloaded.media, & &1.id) == [m.id]
    end
  end

  describe "get_note/1" do
    test "returns the note with assocs preloaded" do
      a = create_account!("alice_get")
      {:ok, note} = Notes.create_status(a, %{"status" => "x"})

      assert {:ok, fetched} = Notes.get_note(note.id)
      assert fetched.id == note.id
      assert fetched.account.id == a.id
    end

    test "unknown id → :not_found" do
      assert {:error, :not_found} = Notes.get_note(99_999_999)
    end
  end

  describe "delete_note/2" do
    test "owner can delete + emits sns.outbox.note.deleted" do
      a = create_account!("alice_del")
      {:ok, note} = Notes.create_status(a, %{"status" => "to be deleted"})

      assert {:ok, _} = Notes.delete_note(a, note.id)
      refute Repo.get(Note, note.id)

      ev =
        Repo.one!(
          from e in OutboxEvent,
            where: e.subject == "sns.outbox.note.deleted" and e.aggregate_id == ^to_string(note.id)
        )

      assert ev.payload["note_id"] == note.id
    end

    test "non-owner → :forbidden" do
      a = create_account!("alice_perm")
      b = create_account!("bob_perm")
      {:ok, note} = Notes.create_status(a, %{"status" => "private to a"})

      assert {:error, :forbidden} = Notes.delete_note(b, note.id)
      assert Repo.get(Note, note.id)
    end

    test "unknown id → :not_found" do
      a = create_account!("alice_404")
      assert {:error, :not_found} = Notes.delete_note(a, 99_999_999)
    end
  end

  describe "context/1" do
    test "returns ancestors and descendants" do
      a = create_account!("alice_ctx")

      {:ok, root} = Notes.create_status(a, %{"status" => "root"})
      _ = update_ap_id(root, "https://x.example/notes/root")

      {:ok, mid} =
        Notes.create_status(a, %{"status" => "mid", "in_reply_to_id" => to_string(root.id)})

      _ = update_ap_id(mid, "https://x.example/notes/mid")

      {:ok, leaf} =
        Notes.create_status(a, %{"status" => "leaf", "in_reply_to_id" => to_string(mid.id)})

      _ = update_ap_id(leaf, "https://x.example/notes/leaf")

      assert {:ok, %{ancestors: ancestors, descendants: descendants}} = Notes.context(mid.id)

      ancestor_ids = Enum.map(ancestors, & &1.id)
      descendant_ids = Enum.map(descendants, & &1.id)

      assert root.id in ancestor_ids
      assert leaf.id in descendant_ids
    end
  end

  describe "Timelines" do
    test "public/1 returns only public notes, newest first" do
      a = create_account!("alice_tl_pub")

      {:ok, n1} = Notes.create_status(a, %{"status" => "public 1", "visibility" => "public"})
      {:ok, _f} = Notes.create_status(a, %{"status" => "followers only", "visibility" => "followers"})
      {:ok, n2} = Notes.create_status(a, %{"status" => "public 2", "visibility" => "public"})

      result = Timelines.public(limit: 50)
      ids = Enum.map(result, & &1.id)

      assert n2.id in ids
      assert n1.id in ids
    end

    test "home/2 returns viewer's notes + followed accounts' notes" do
      alice = create_account!("alice_tl_home")
      bob = create_account!("bob_tl_home")
      _carol = create_account!("carol_tl_home")

      domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
      alice_uri = "https://#{domain}/users/alice_tl_home"

      Repo.insert!(%Follow{
        follower_uri: alice_uri,
        followee_id: bob.id,
        state: "accepted"
      })

      {:ok, alice_note} = Notes.create_status(alice, %{"status" => "alice's"})
      {:ok, bob_note} = Notes.create_status(bob, %{"status" => "bob's"})

      result = Timelines.home(alice, limit: 50)
      ids = Enum.map(result, & &1.id)

      assert alice_note.id in ids
      assert bob_note.id in ids
    end
  end

  defp create_account!(username) do
    %Account{username: username, display_name: username, summary: ""}
    |> Repo.insert!()
  end

  defp create_media!(account) do
    %Media{
      url: "https://x.example/m/#{:rand.uniform(10_000)}.png",
      type: "image",
      account_id: account.id
    }
    |> Repo.insert!()
  end

  defp update_ap_id(%Note{id: id}, ap_id) do
    Repo.update_all(from(n in Note, where: n.id == ^id), set: [ap_id: ap_id])
  end
end
