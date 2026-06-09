# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Integration.PollsTest do
  use SukhiFedi.IntegrationCase, async: false

  @moduletag :integration

  import Ecto.Query

  alias SukhiFedi.{Notes, Polls}
  alias SukhiFedi.Schema.{Account, Poll, PollOption}

  describe "create_status with poll[…]" do
    test "JSON shape: poll: %{options, expires_in, multiple}" do
      a = create_account!("alice_p_j")

      {:ok, note} =
        Notes.create_status(a, %{
          "status" => "favorite color?",
          "poll" => %{
            "options" => ["red", "blue", "green"],
            "expires_in" => 3600,
            "multiple" => false
          }
        })

      assert [%Poll{id: pid, multiple: false}] =
               Repo.all(from p in Poll, where: p.note_id == ^note.id)

      assert ["red", "blue", "green"] =
               Repo.all(
                 from o in PollOption,
                   where: o.poll_id == ^pid,
                   order_by: [asc: o.position],
                   select: o.title
               )
    end

    test "form shape: poll[options][]" do
      a = create_account!("alice_p_f")

      {:ok, note} =
        Notes.create_status(a, %{
          "status" => "binary",
          "poll[options][]" => ["yes", "no"],
          "poll[expires_in]" => "60",
          "poll[multiple]" => "false"
        })

      [%Poll{id: pid}] = Repo.all(from p in Poll, where: p.note_id == ^note.id)
      assert ["yes", "no"] =
               Repo.all(
                 from o in PollOption,
                   where: o.poll_id == ^pid,
                   order_by: [asc: o.position],
                   select: o.title
               )
    end

    test "fewer than two options rolls the whole transaction back" do
      a = create_account!("alice_p_bad")

      assert {:error, :poll_needs_two_options} =
               Notes.create_status(a, %{
                 "status" => "lonely",
                 "poll" => %{"options" => ["only"]}
               })

      # No note was inserted either — the Multi rollback should be atomic.
      assert Repo.aggregate(from(n in SukhiFedi.Schema.Note, where: n.account_id == ^a.id), :count, :id) == 0
    end
  end

  describe "Polls.get_with_results/2 and vote/3" do
    test "vote tallies + idempotency + own_votes for the viewer" do
      a = create_account!("alice_pv")
      b = create_account!("bob_pv")

      {:ok, note} =
        Notes.create_status(a, %{
          "status" => "?",
          "poll" => %{"options" => ["x", "y"], "expires_in" => 3600}
        })

      [%Poll{id: pid}] = Repo.all(from p in Poll, where: p.note_id == ^note.id)

      assert :ok = Polls.vote(b.id, pid, [0])
      # double-voting collapses to one row via the unique constraint
      assert :ok = Polls.vote(b.id, pid, [0])

      {:ok, ctx} = Polls.get_with_results(pid, b.id)
      assert ctx.tallies[Enum.at(ctx.options, 0).id] == 1
      assert ctx.voted? == true
      assert ctx.voted_option_ids == [Enum.at(ctx.options, 0).id]
      assert ctx.voters_count == 1
    end

    test "single-choice poll rejects multiple choices" do
      a = create_account!("alice_pv2")
      b = create_account!("bob_pv2")

      {:ok, note} =
        Notes.create_status(a, %{
          "status" => "?",
          "poll" => %{"options" => ["x", "y"], "multiple" => false}
        })

      [%Poll{id: pid}] = Repo.all(from p in Poll, where: p.note_id == ^note.id)
      assert {:error, :too_many_choices} = Polls.vote(b.id, pid, [0, 1])
    end

    test "single-choice re-vote replaces the prior ballot, no stuffing (C6)" do
      a = create_account!("alice_pv_rb")
      b = create_account!("bob_pv_rb")

      {:ok, note} =
        Notes.create_status(a, %{
          "status" => "?",
          "poll" => %{"options" => ["x", "y"], "multiple" => false}
        })

      [%Poll{id: pid}] = Repo.all(from p in Poll, where: p.note_id == ^note.id)

      assert :ok = Polls.vote(b.id, pid, [0])
      assert :ok = Polls.vote(b.id, pid, [1])

      {:ok, ctx} = Polls.get_with_results(pid, b.id)
      opt0 = Enum.at(ctx.options, 0).id
      opt1 = Enum.at(ctx.options, 1).id

      assert ctx.tallies[opt0] in [nil, 0]
      assert ctx.tallies[opt1] == 1
      assert ctx.voted_option_ids == [opt1]
      assert ctx.voters_count == 1
    end

    test "expired poll rejects votes" do
      a = create_account!("alice_pv3")
      b = create_account!("bob_pv3")

      {:ok, note} =
        Notes.create_status(a, %{
          "status" => "?",
          "poll" => %{"options" => ["x", "y"]}
        })

      [poll] = Repo.all(from p in Poll, where: p.note_id == ^note.id)

      expired_at = DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.truncate(:second)
      poll
      |> Ecto.Changeset.change(%{expires_at: expired_at})
      |> Repo.update!()

      assert {:error, :expired} = Polls.vote(b.id, poll.id, [0])
    end
  end

  defp create_account!(username) do
    %Account{username: username, display_name: username, summary: ""}
    |> Repo.insert!()
  end
end
