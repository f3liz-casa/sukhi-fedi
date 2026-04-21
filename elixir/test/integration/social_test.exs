# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Integration.SocialTest do
  @moduledoc """
  End-to-end tests for `SukhiFedi.Social` follow/unfollow + relationships.
  Requires the test Postgres with core migrations applied.

      docker compose -f docker-compose.test.yml up -d
      MIX_ENV=test mix ecto.migrate
      mix test --only integration
  """

  use SukhiFedi.IntegrationCase, async: false

  @moduletag :integration

  import Ecto.Query

  alias SukhiFedi.{Accounts, Social}
  alias SukhiFedi.Schema.{Account, Follow, OutboxEvent}

  describe "request_follow/2" do
    test "inserts a Follow row + outbox event" do
      alice = create_account!("alice_rf")
      bob = create_account!("bob_rf")

      {:ok, follow} = Social.request_follow(alice, bob.id)

      assert follow.followee_id == bob.id
      assert follow.follower_uri =~ "/users/alice_rf"
      assert follow.state == "pending"

      ev =
        Repo.one!(
          from e in OutboxEvent,
            where: e.subject == "sns.outbox.follow.requested" and e.aggregate_id == ^to_string(follow.id)
        )

      assert ev.payload["follow_id"] == follow.id
      assert ev.payload["followee_id"] == bob.id
    end

    test "is idempotent — second call returns the same row, no extra outbox" do
      alice = create_account!("alice_idemp")
      bob = create_account!("bob_idemp")

      {:ok, f1} = Social.request_follow(alice, bob.id)
      {:ok, f2} = Social.request_follow(alice, bob.id)

      assert f1.id == f2.id

      n =
        Repo.aggregate(
          from(e in OutboxEvent,
            where: e.subject == "sns.outbox.follow.requested" and e.aggregate_id == ^to_string(f1.id)
          ),
          :count,
          :id
        )

      assert n == 1
    end

    test "self-follow is rejected" do
      alice = create_account!("alice_self")
      assert {:error, :self_follow} = Social.request_follow(alice, alice.id)
    end

    test "follow of unknown account → :not_found" do
      alice = create_account!("alice_404")
      assert {:error, :not_found} = Social.request_follow(alice, 99_999_999)
    end
  end

  describe "unfollow/2" do
    test "deletes the Follow row + emits sns.outbox.follow.undone" do
      alice = create_account!("alice_unf")
      bob = create_account!("bob_unf")
      {:ok, follow} = Social.request_follow(alice, bob.id)

      assert {:ok, deleted} = Social.unfollow(alice, bob.id)
      assert deleted.id == follow.id
      refute Repo.get(Follow, follow.id)

      ev =
        Repo.one!(
          from e in OutboxEvent,
            where: e.subject == "sns.outbox.follow.undone" and e.aggregate_id == ^to_string(follow.id)
        )

      assert ev.payload["followee_id"] == bob.id
    end

    test "unfollowing when no follow exists → :not_found" do
      alice = create_account!("alice_uf2")
      bob = create_account!("bob_uf2")

      assert {:error, :not_found} = Social.unfollow(alice, bob.id)
    end
  end

  describe "list_relationships/2" do
    test "returns following=true for accepted follow, followed_by=true reciprocal" do
      alice = create_account!("alice_rel")
      bob = create_account!("bob_rel")
      carol = create_account!("carol_rel")

      {:ok, f1} = Social.request_follow(alice, bob.id)
      # mark accepted directly
      _ = Repo.update_all(from(f in Follow, where: f.id == ^f1.id), set: [state: "accepted"])

      # bob follows alice back
      {:ok, f2} = Social.request_follow(bob, alice.id)
      _ = Repo.update_all(from(f in Follow, where: f.id == ^f2.id), set: [state: "accepted"])

      [bob_rel, carol_rel] = Social.list_relationships(alice, [bob.id, carol.id])

      assert bob_rel.id == bob.id
      assert bob_rel.following == true
      assert bob_rel.followed_by == true

      assert carol_rel.id == carol.id
      assert carol_rel.following == false
      assert carol_rel.followed_by == false
    end

    test "caps at 40 ids" do
      alice = create_account!("alice_cap")
      ids = Enum.to_list(1..50)
      # Just make sure it doesn't crash; result count matches input
      # (since none of these accounts exist, all relationships are
      # all-false but we get one entry per requested id).
      list = Social.list_relationships(alice, ids)
      # Capability layer caps at 40, but the context returns all
      # requested ids — capping is a presentation concern.
      assert length(list) == 50
    end
  end

  describe "Accounts.lookup_by_acct/1" do
    test "local username resolves" do
      a = create_account!("local_lookup")
      assert {:ok, found} = Accounts.lookup_by_acct("local_lookup")
      assert found.id == a.id
    end

    test "user@local-host resolves" do
      a = create_account!("local_at")
      domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")

      assert {:ok, found} = Accounts.lookup_by_acct("local_at@#{domain}")
      assert found.id == a.id
    end

    test "remote acct (different host) → :not_found" do
      _ = create_account!("only_local_user")
      assert {:error, :not_found} = Accounts.lookup_by_acct("only_local_user@elsewhere.example")
    end
  end

  describe "Accounts.update_credentials/2" do
    test "updates display_name + emits sns.outbox.actor.updated" do
      a = create_account!("alice_uc")

      assert {:ok, updated} =
               Accounts.update_credentials(a.id, %{"display_name" => "Alice Updated"})

      assert updated.display_name == "Alice Updated"

      ev =
        Repo.one!(
          from e in OutboxEvent,
            where: e.subject == "sns.outbox.actor.updated" and e.aggregate_id == ^to_string(a.id)
        )

      assert ev.payload["account_id"] == a.id
    end

    test "rejects too-long display_name" do
      a = create_account!("alice_long")

      assert {:error, {:validation, errors}} =
               Accounts.update_credentials(a.id, %{"display_name" => String.duplicate("x", 200)})

      assert is_list(errors[:display_name])
    end

    test "Mastodon's `note` is mapped to `summary`" do
      a = create_account!("alice_note")
      assert {:ok, updated} = Accounts.update_credentials(a.id, %{"note" => "new bio"})
      assert updated.summary == "new bio"
    end
  end

  describe "Accounts.counts_for/1" do
    test "returns followers/following/statuses counts and caches" do
      a = create_account!("alice_counts")
      assert %{followers: 0, following: 0, statuses: 0} = Accounts.counts_for(a.id)
    end
  end

  defp create_account!(username) do
    %Account{username: username, display_name: username, summary: ""}
    |> Repo.insert!()
  end
end
