# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Fedi.InboxTest do
  use ExUnit.Case, async: true

  alias SukhiFedi.Fedi.Inbox

  @follow %{
    "@context" => "https://www.w3.org/ns/activitystreams",
    "id" => "https://remote.test/follows/1",
    "type" => "Follow",
    "actor" => "https://remote.test/users/friend",
    "object" => "https://sukhi.test/users/shiro"
  }

  defp resolving_fetch(actor_doc) do
    fn _uri, _sign_as -> {:ok, %{"document" => actor_doc}} end
  end

  test "Follow resolves the actor and replies with an Accept" do
    fetch = resolving_fetch(%{"inbox" => "https://remote.test/users/friend/inbox"})

    assert {:ok, instruction} =
             Inbox.handle(%{"raw" => @follow, "selfDomain" => "sukhi.test"}, fetch)

    assert %{
             "action" => "save_and_reply",
             "save" => %{"follow" => @follow, "followeeUri" => "https://sukhi.test/users/shiro"},
             "reply" => reply,
             "inbox" => "https://remote.test/users/friend/inbox"
           } = instruction

    assert reply["type"] == "Accept"
    assert reply["actor"] == "https://sukhi.test/users/shiro"
    assert String.starts_with?(reply["id"], "https://sukhi.test/activities/accept/")

    # The embedded Follow stub carries everything receivers match on.
    assert reply["object"] == %{
             "id" => "https://remote.test/follows/1",
             "type" => "Follow",
             "actor" => "https://remote.test/users/friend",
             "object" => "https://sukhi.test/users/shiro"
           }
  end

  test "Follow with an embedded actor object still resolves" do
    follow = Map.put(@follow, "actor", %{"id" => "https://remote.test/users/friend"})
    fetch = resolving_fetch(%{"inbox" => "https://remote.test/users/friend/inbox"})

    assert {:ok, %{"action" => "save_and_reply"}} =
             Inbox.handle(%{"raw" => follow, "selfDomain" => "sukhi.test"}, fetch)
  end

  test "Follow whose actor cannot be resolved is ignored, not failed" do
    fetch = fn _uri, _sign_as -> {:error, {:http_status, 410}} end

    assert {:ok, %{"action" => "ignore"}} =
             Inbox.handle(%{"raw" => @follow, "selfDomain" => "sukhi.test"}, fetch)
  end

  test "Follow missing ids is ignored" do
    fetch = resolving_fetch(%{"inbox" => "https://remote.test/inbox"})
    follow = Map.delete(@follow, "object")

    assert {:ok, %{"action" => "ignore"}} = Inbox.handle(%{"raw" => follow}, fetch)
  end

  test "known generic activities pass through as save with the raw activity" do
    raw = %{"type" => "Create", "id" => "https://remote.test/creates/1", "actor" => "x"}
    fetch = fn _, _ -> flunk("must not fetch for generic activities") end

    assert {:ok, %{"action" => "save", "object" => ^raw}} =
             Inbox.handle(%{"raw" => raw}, fetch)
  end

  test "unknown or missing types are ignored" do
    fetch = fn _, _ -> flunk("must not fetch") end

    assert {:ok, %{"action" => "ignore"}} = Inbox.handle(%{"raw" => %{"type" => "Borrow"}}, fetch)
    assert {:ok, %{"action" => "ignore"}} = Inbox.handle(%{"raw" => %{}}, fetch)
    assert {:ok, %{"action" => "ignore"}} = Inbox.handle(%{"raw" => %{"type" => ["Create"]}}, fetch)
  end
end
