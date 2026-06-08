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
  end

  defp create_account!(username) do
    %Account{username: username, display_name: username, summary: ""}
    |> Repo.insert!()
  end
end
