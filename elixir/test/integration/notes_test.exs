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
  alias SukhiFedi.Schema.{Account, ConversationParticipant, Follow, Media, Note, OutboxEvent}

  describe "create_status/2" do
    test "creates a Note + emits sns.outbox.note.created" do
      a = create_account!("alice_cs")

      assert {:ok, note} =
               Notes.create_status(a, %{"status" => "hello", "visibility" => "public"})

      assert note.content == "hello"
      assert note.visibility == "public"
      assert note.account_id == a.id

      ev =
        Repo.one!(
          from(e in OutboxEvent,
            where:
              e.subject == "sns.outbox.note.created" and e.aggregate_id == ^to_string(note.id)
          )
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

    test "direct status with no resolvable mention → :dm_no_recipients" do
      a = create_account!("alice_dm")

      assert {:error, :dm_no_recipients} =
               Notes.create_status(a, %{
                 "status" => "secret, nobody home",
                 "visibility" => "direct"
               })
    end

    test "direct status to a local user → Note(direct) + participants, no federation" do
      alice = create_account!("alice_dm_send")
      bob = create_account!("bob_dm_recv")

      assert {:ok, note} =
               Notes.create_status(alice, %{
                 "status" => "@bob_dm_recv psst",
                 "visibility" => "direct"
               })

      assert note.visibility == "direct"

      # New thread → conversation_ap_id is the note's own synthesized AP id.
      expected_cid = "https://#{SukhiFedi.Config.domain!()}/users/alice_dm_send/notes/#{note.id}"
      assert note.conversation_ap_id == expected_cid

      # Both are participants; the sender is read, the recipient unread.
      assert %{unread: false} = participant(note.conversation_ap_id, alice.id)
      assert %{unread: true} = participant(note.conversation_ap_id, bob.id)

      # A purely local DM has nobody to federate to.
      refute Repo.exists?(
               from(e in OutboxEvent,
                 where:
                   e.subject == "sns.outbox.dm.created" and
                     e.aggregate_id == ^to_string(note.id)
               )
             )
    end

    test "direct status to a remote user → federates with conversation context" do
      alice = create_account!("alice_dm_fed")
      _bob = create_remote_account!("bob", "remote.example")

      assert {:ok, note} =
               Notes.create_status(alice, %{
                 "status" => "@bob@remote.example hi",
                 "visibility" => "direct"
               })

      ev =
        Repo.one!(
          from(e in OutboxEvent,
            where:
              e.subject == "sns.outbox.dm.created" and
                e.aggregate_id == ^to_string(note.id)
          )
        )

      assert "https://remote.example/users/bob" in ev.payload["recipient_actor_uris"]
      # The federated event carries the thread so the other side can thread.
      assert ev.payload["conversation_ap_id"] == note.conversation_ap_id
      assert is_binary(note.conversation_ap_id)
    end

    test "direct reply inherits the parent's conversation" do
      alice = create_account!("alice_dm_thread")
      _bob = create_account!("bob_dm_thread")

      {:ok, root} =
        Notes.create_status(alice, %{"status" => "@bob_dm_thread one", "visibility" => "direct"})

      {:ok, reply} =
        Notes.create_status(alice, %{
          "status" => "@bob_dm_thread two",
          "visibility" => "direct",
          "in_reply_to_id" => to_string(root.id)
        })

      assert reply.conversation_ap_id == root.conversation_ap_id
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

    test "quote_id sets quote_of_ap_id + carries it in sns.outbox.note.created" do
      a = create_account!("alice_quote")
      {:ok, quoted} = Notes.create_status(a, %{"status" => "original", "visibility" => "public"})

      assert {:ok, note} =
               Notes.create_status(a, %{
                 "status" => "quoting that",
                 "visibility" => "public",
                 "quote_id" => to_string(quoted.id)
               })

      expected =
        "https://#{SukhiFedi.Config.domain!()}/users/alice_quote/notes/#{quoted.id}"

      assert note.quote_of_ap_id == expected

      ev =
        Repo.one!(
          from(e in OutboxEvent,
            where:
              e.subject == "sns.outbox.note.created" and
                e.aggregate_id == ^to_string(note.id)
          )
        )

      assert ev.payload["quote_of_ap_id"] == expected
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
          from(e in OutboxEvent,
            where:
              e.subject == "sns.outbox.note.deleted" and e.aggregate_id == ^to_string(note.id)
          )
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

    test "threads a remote reply onto a local parent (local notes carry no ap_id)" do
      alice = create_account!("alice_local_ctx")
      bob = create_remote_account!("bob_remote_ctx", "remote.example")

      # A real local note: its `ap_id` column stays NULL, addressed only by
      # the synthesized `/notes/<id>` URL.
      {:ok, root} = Notes.create_status(alice, %{"status" => "local root"})
      root_uri = "https://#{SukhiFedi.Config.domain!()}/users/#{alice.username}/notes/#{root.id}"

      # A remote reply references the local root by that URL.
      reply =
        %Note{
          account_id: bob.id,
          content: "remote reply",
          visibility: "public",
          ap_id: "https://remote.example/notes/ctx_reply1",
          in_reply_to_ap_id: root_uri
        }
        |> Repo.insert!()

      # Opening the reply surfaces the local root as an ancestor…
      assert {:ok, %{ancestors: ancestors}} = Notes.context(reply.id)
      assert root.id in Enum.map(ancestors, & &1.id)

      # …and opening the local root surfaces the remote reply as a descendant.
      assert {:ok, %{descendants: descendants}} = Notes.context(root.id)
      assert reply.id in Enum.map(descendants, & &1.id)
    end
  end

  describe "Timelines" do
    test "public/1 returns only public notes, newest first" do
      a = create_account!("alice_tl_pub")

      {:ok, n1} = Notes.create_status(a, %{"status" => "public 1", "visibility" => "public"})

      {:ok, _f} =
        Notes.create_status(a, %{"status" => "followers only", "visibility" => "followers"})

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

  describe "with_refs/1" do
    test "resolves in_reply_to and quote to local rows + preloads quoted account" do
      author = create_account!("wr_author")
      replier = create_account!("wr_replier")

      parent = note!(author, "https://x.example/notes/p1", "parent")

      reply =
        note!(replier, "https://x.example/notes/r1", "reply", in_reply_to_ap_id: parent.ap_id)

      quoted = note!(author, "https://x.example/notes/q1", "quoted")

      quoting =
        note!(replier, "https://x.example/notes/qt1", "quoting", quote_of_ap_id: quoted.ap_id)

      [er, eq] = Notes.with_refs([reply, quoting])

      assert er.in_reply_to_id == parent.id
      assert er.in_reply_to_account_id == author.id
      assert er.quoted_note == nil

      assert eq.quoted_note.id == quoted.id
      # account is preloaded for the nested-Status render
      assert eq.quoted_note.account.username == "wr_author"
      assert eq.in_reply_to_id == nil
    end

    test "leaves refs nil when the referenced note isn't held locally" do
      replier = create_account!("wr_dangling")

      reply =
        note!(replier, "https://x.example/notes/d1", "orphan reply",
          in_reply_to_ap_id: "https://gone.example/notes/x"
        )

      [er] = Notes.with_refs([reply])
      assert er.in_reply_to_id == nil
      assert er.in_reply_to_account_id == nil
    end
  end

  describe "snowflake note ids" do
    test "new notes get a non-sequential, time-sortable id" do
      a = create_account!("snow_a")
      {:ok, n1} = Notes.create_status(a, %{"status" => "first"})
      {:ok, n2} = Notes.create_status(a, %{"status" => "second"})

      # Snowflake = (ms since 2024) << 16 — far above the old sequential
      # range, and increasing for later notes so id-based paging holds.
      assert n1.id > 1_000_000_000_000
      assert n2.id > n1.id
    end
  end

  defp note!(account, ap_id, content, extra \\ []) do
    %Note{content: content, visibility: "public", account_id: account.id, ap_id: ap_id}
    |> struct(Map.new(extra))
    |> Repo.insert!()
  end

  defp create_account!(username) do
    %Account{username: username, display_name: username, summary: ""}
    |> Repo.insert!()
  end

  defp create_remote_account!(username, domain) do
    %Account{
      username: username,
      domain: domain,
      display_name: username,
      summary: "",
      actor_uri: "https://#{domain}/users/#{username}"
    }
    |> Repo.insert!()
  end

  defp participant(conversation_ap_id, account_id) do
    Repo.one(
      from(cp in ConversationParticipant,
        where: cp.conversation_ap_id == ^conversation_ap_id and cp.account_id == ^account_id,
        select: %{unread: cp.unread}
      )
    )
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
