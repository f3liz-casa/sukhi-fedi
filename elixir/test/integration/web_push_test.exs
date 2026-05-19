# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Integration.WebPushTest do
  use SukhiFedi.IntegrationCase, async: false

  @moduletag :integration

  alias SukhiFedi.Addons.WebPush
  alias SukhiFedi.Schema.Account

  describe "subscribe/5 + get_subscription_for/1" do
    test "upserts on (account, endpoint) and surfaces the most-recent row" do
      alice = create_account!("alice_wp")

      endpoint = "https://push.example/sub/1"
      {:ok, _} = WebPush.subscribe(alice.id, endpoint, "p256dh", "auth", %{"mention" => true})

      # Same endpoint re-issued with different alerts → row is replaced.
      {:ok, _} = WebPush.subscribe(alice.id, endpoint, "p256dh", "auth", %{"mention" => false})

      sub = WebPush.get_subscription_for(alice.id)
      assert sub.endpoint == endpoint
      assert sub.alerts == %{"mention" => false}

      case WebPush.unsubscribe(endpoint) do
        {n, _} when n >= 0 -> :ok
        :ok -> :ok
      end

      assert WebPush.get_subscription_for(alice.id) == nil
    end

    test "server_key reads from app config" do
      Application.put_env(:sukhi_fedi, :vapid_public_key, "test-key")
      assert WebPush.server_key() == "test-key"
      Application.delete_env(:sukhi_fedi, :vapid_public_key)
      assert WebPush.server_key() == nil
    end
  end

  defp create_account!(username) do
    %Account{username: username, display_name: username, summary: ""}
    |> Repo.insert!()
  end
end
