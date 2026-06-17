# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Integration.TimelinesTest do
  use SukhiFedi.IntegrationCase, async: false

  @moduletag :integration

  alias SukhiFedi.{Lists, Notes, Social, Timelines}
  alias SukhiFedi.Schema.{Account, Note}

  describe "home/2 with circles" do
    test "an exclusive circle's members leave home but stay in the circle feed" do
      alice = create_account!("alice_home")
      bob = create_account!("bob_home")

      # alice follows bob, both have a note → home shows both
      {:ok, _} = Social.request_follow(alice, bob.id)
      {:ok, _} = Notes.create_status(alice, %{"status" => "from alice"})
      {:ok, _} = Notes.create_status(bob, %{"status" => "from bob"})

      home_before = Timelines.home(alice)
      assert Enum.any?(home_before, &(Map.get(&1, :account_id) == bob.id))
      assert Enum.any?(home_before, &(Map.get(&1, :account_id) == alice.id))

      # move bob into an *exclusive* circle (follow is untouched)
      {:ok, circle} = Lists.create(alice.id, %{title: "quiet", exclusive: true})
      :ok = Lists.add_accounts(alice.id, circle.id, [bob.id])

      # home drops bob, keeps alice's own note
      home_after = Timelines.home(alice)
      refute Enum.any?(home_after, &(Map.get(&1, :account_id) == bob.id))
      assert Enum.any?(home_after, &(Map.get(&1, :account_id) == alice.id))

      # but bob is still readable in the circle's own feed
      {:ok, feed} = Lists.timeline(alice.id, circle.id)
      assert Enum.any?(feed, &(&1.account_id == bob.id))
    end

    test "a circle member's reply to a post on this server still reaches home" do
      alice = create_account!("alice_rep")
      bob = create_account!("bob_rep")

      {:ok, _} = Social.request_follow(alice, bob.id)
      {:ok, circle} = Lists.create(alice.id, %{title: "quiet", exclusive: true})
      :ok = Lists.add_accounts(alice.id, circle.id, [bob.id])

      domain = SukhiFedi.Config.domain!()

      # a plain post from bob → hidden (he's in an exclusive circle)
      {:ok, soliloquy} = Notes.create_status(bob, %{"status" => "thinking out loud"})
      # bob replying to a post on this server (≈ to alice) → still reaches home
      reply =
        %Note{}
        |> Note.changeset(%{
          account_id: bob.id,
          content: "@alice hey",
          visibility: "public",
          in_reply_to_ap_id: "https://#{domain}/users/alice_rep/statuses/1"
        })
        |> Repo.insert!()

      home = Timelines.home(alice)
      ids = Enum.map(home, &Map.get(&1, :id))

      assert reply.id in ids
      refute soliloquy.id in ids
    end
  end

  describe "home/2 filters" do
    test "hide_sensitive drops sensitive and CW posts" do
      alice = create_account!("alice_filt")
      {:ok, plain} = Notes.create_status(alice, %{"status" => "plain"})

      sens =
        %Note{}
        |> Note.changeset(%{
          account_id: alice.id,
          content: "nsfw",
          visibility: "public",
          sensitive: true
        })
        |> Repo.insert!()

      cw =
        %Note{}
        |> Note.changeset(%{
          account_id: alice.id,
          content: "spoiler",
          visibility: "public",
          cw: "warning"
        })
        |> Repo.insert!()

      all_ids = alice |> Timelines.home() |> Enum.map(&Map.get(&1, :id))
      assert sens.id in all_ids
      assert cw.id in all_ids

      kept = alice |> Timelines.home(hide_sensitive: true) |> Enum.map(&Map.get(&1, :id))
      assert plain.id in kept
      refute sens.id in kept
      refute cw.id in kept
    end

    test "a non-exclusive list's hide_sensitive filter narrows its members in home" do
      alice = create_account!("alice_pl")
      bob = create_account!("bob_pl")

      {:ok, _} = Social.request_follow(alice, bob.id)

      {:ok, list} =
        Lists.create(alice.id, %{title: "filtered", exclusive: false, filter_hide_sensitive: true})

      :ok = Lists.add_accounts(alice.id, list.id, [bob.id])

      {:ok, plain} = Notes.create_status(bob, %{"status" => "ok"})

      sens =
        %Note{}
        |> Note.changeset(%{
          account_id: bob.id,
          content: "nsfw",
          visibility: "public",
          sensitive: true
        })
        |> Repo.insert!()

      ids = alice |> Timelines.home() |> Enum.map(&Map.get(&1, :id))
      # 通常投稿は出る。sensitive は per-list filter(hide_sensitive)で消える。
      assert plain.id in ids
      refute sens.id in ids
    end

    test "a hide-replies list drops members' replies from home, keeps top-level posts" do
      alice = create_account!("alice_hr")
      bob = create_account!("bob_hr")
      {:ok, _} = Social.request_follow(alice, bob.id)

      {:ok, list} =
        Lists.create(alice.id, %{title: "no replies", exclusive: false, filter_replies: "hide"})

      :ok = Lists.add_accounts(alice.id, list.id, [bob.id])

      {:ok, top} = Notes.create_status(bob, %{"status" => "top level"})

      reply =
        %Note{}
        |> Note.changeset(%{
          account_id: bob.id,
          content: "a reply",
          visibility: "public",
          in_reply_to_ap_id: "https://remote.example/users/x/statuses/1"
        })
        |> Repo.insert!()

      ids = alice |> Timelines.home() |> Enum.map(&Map.get(&1, :id))
      assert top.id in ids
      refute reply.id in ids
    end

    test "a replies-to-me list keeps replies to a post here, drops replies elsewhere" do
      alice = create_account!("alice_rtm")
      bob = create_account!("bob_rtm")
      {:ok, _} = Social.request_follow(alice, bob.id)

      {:ok, list} =
        Lists.create(alice.id, %{title: "to me", exclusive: false, filter_replies: "to_me"})

      :ok = Lists.add_accounts(alice.id, list.id, [bob.id])

      domain = SukhiFedi.Config.domain!()
      {:ok, top} = Notes.create_status(bob, %{"status" => "top level"})

      to_here =
        %Note{}
        |> Note.changeset(%{
          account_id: bob.id,
          content: "@alice hi",
          visibility: "public",
          in_reply_to_ap_id: "https://#{domain}/users/alice_rtm/statuses/1"
        })
        |> Repo.insert!()

      elsewhere =
        %Note{}
        |> Note.changeset(%{
          account_id: bob.id,
          content: "talking to someone else",
          visibility: "public",
          in_reply_to_ap_id: "https://remote.example/users/x/statuses/1"
        })
        |> Repo.insert!()

      ids = alice |> Timelines.home() |> Enum.map(&Map.get(&1, :id))
      assert top.id in ids
      assert to_here.id in ids
      refute elsewhere.id in ids
    end

    test "a keyword list admits only members' posts matching the keyword in content" do
      alice = create_account!("alice_kw")
      bob = create_account!("bob_kw")
      {:ok, _} = Social.request_follow(alice, bob.id)

      {:ok, list} =
        Lists.create(alice.id, %{title: "garden", exclusive: false, filter_keyword: "garden"})

      :ok = Lists.add_accounts(alice.id, list.id, [bob.id])

      {:ok, match} = Notes.create_status(bob, %{"status" => "my garden today"})
      {:ok, miss} = Notes.create_status(bob, %{"status" => "hello world"})

      ids = alice |> Timelines.home() |> Enum.map(&Map.get(&1, :id))
      assert match.id in ids
      refute miss.id in ids
    end

    test "a keyword list with a leading # matches the hashtag" do
      alice = create_account!("alice_tag")
      bob = create_account!("bob_tag")
      {:ok, _} = Social.request_follow(alice, bob.id)

      {:ok, list} =
        Lists.create(alice.id, %{title: "cats", exclusive: false, filter_keyword: "#cats"})

      :ok = Lists.add_accounts(alice.id, list.id, [bob.id])

      {:ok, tagged} = Notes.create_status(bob, %{"status" => "look at my #cats"})
      {:ok, untagged} = Notes.create_status(bob, %{"status" => "a dog post"})

      ids = alice |> Timelines.home() |> Enum.map(&Map.get(&1, :id))
      assert tagged.id in ids
      refute untagged.id in ids
    end
  end

  defp create_account!(username) do
    %Account{username: username, display_name: username, summary: ""}
    |> Repo.insert!()
  end
end
