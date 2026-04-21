# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Outbox.ConsumerTest do
  use ExUnit.Case, async: true

  alias SukhiDelivery.Outbox.Consumer

  describe "handle_event/2 — routing without DB" do
    test "actor.updated is explicitly skipped" do
      assert :skipped =
               Consumer.handle_event(
                 "sns.outbox.actor.updated",
                 ~s({"account_id":1,"username":"alice"})
               )
    end

    test "oauth.app_registered is explicitly ignored (local-only)" do
      assert :ignored =
               Consumer.handle_event(
                 "sns.outbox.oauth.app_registered",
                 ~s({"app_id":1,"name":"smoke"})
               )
    end

    test "unknown subject returns :no_handler" do
      assert :no_handler =
               Consumer.handle_event(
                 "sns.outbox.totally.unknown",
                 ~s({"x":1})
               )
    end

    test "malformed JSON is logged but doesn't crash" do
      assert :bad_json =
               Consumer.handle_event("sns.outbox.note.created", "{not json")
    end

    test "non-binary subject body is rejected" do
      # The subscription delivers binary bodies; nothing else is even
      # reachable here. But be defensive: empty string is invalid JSON.
      assert :bad_json = Consumer.handle_event("sns.outbox.note.created", "")
    end
  end

  describe "dispatch/2 — pure routing surface" do
    test "follow.requested missing fields → :missing_fields without crashing" do
      assert :missing_fields = Consumer.dispatch("sns.outbox.follow.requested", %{})
    end

    test "like.created missing fields → :missing_fields" do
      assert :missing_fields = Consumer.dispatch("sns.outbox.like.created", %{})
    end

    test "announce.undone missing fields → :missing_fields" do
      assert :missing_fields = Consumer.dispatch("sns.outbox.announce.undone", %{})
    end

    test "add.created missing fields → :missing_fields" do
      assert :missing_fields = Consumer.dispatch("sns.outbox.add.created", %{})
    end

    test "note.created missing account → :missing_account" do
      assert :missing_account = Consumer.dispatch("sns.outbox.note.created", %{})
    end

    test "note.deleted missing fields → :missing_fields" do
      assert :missing_fields = Consumer.dispatch("sns.outbox.note.deleted", %{})
    end
  end
end
