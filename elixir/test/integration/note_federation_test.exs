# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule SukhiFedi.Integration.NoteFederationTest do
  @moduledoc """
  Inbound federation scenarios applied by `SukhiFedi.AP.Instructions`.

      docker compose -f docker-compose.test.yml up -d
      MIX_ENV=test mix ecto.migrate
      mix test --only integration
  """

  use SukhiFedi.IntegrationCase, async: false

  @moduletag :integration

  alias SukhiFedi.{Config, Notes}
  alias SukhiFedi.AP.Instructions
  alias SukhiFedi.Schema.{Account, Notification, Reaction}

  describe "stage-0 smoke" do
    test "mock remote bypass is openable", %{mock_remote: bypass} do
      assert is_integer(bypass.port)
      assert bypass.port > 0
    end
  end

  describe "inbound reactions (Like / EmojiReact)" do
    test "EmojiReact materialises a reactions row + favourite notification" do
      author = create_account!("emoji_author")
      reactor = create_remote_account!("emoji_reactor", "remote.example")
      {:ok, note} = Notes.create_status(author, %{"status" => "react to me"})

      assert :ok =
               Instructions.execute(%{
                 "action" => "save",
                 "object" => %{
                   "type" => "EmojiReact",
                   "actor" => reactor.actor_uri,
                   "object" => local_note_uri(author, note),
                   "content" => "🦊"
                 }
               })

      assert Repo.get_by(Reaction, account_id: reactor.id, note_id: note.id, emoji: "🦊")

      assert Repo.get_by(Notification,
               account_id: author.id,
               from_account_id: reactor.id,
               note_id: note.id,
               type: "favourite"
             )
    end

    test "Like materialises a star reaction" do
      author = create_account!("like_author")
      reactor = create_remote_account!("like_reactor", "remote.example")
      {:ok, note} = Notes.create_status(author, %{"status" => "like me"})

      assert :ok =
               Instructions.execute(%{
                 "action" => "save",
                 "object" => %{
                   "type" => "Like",
                   "actor" => reactor.actor_uri,
                   "object" => local_note_uri(author, note)
                 }
               })

      assert Repo.get_by(Reaction, account_id: reactor.id, note_id: note.id, emoji: "⭐")
    end

    test "Undo(EmojiReact) removes the reaction row" do
      author = create_account!("undo_author")
      reactor = create_remote_account!("undo_reactor", "remote.example")
      {:ok, note} = Notes.create_status(author, %{"status" => "undo me"})

      react = %{
        "type" => "EmojiReact",
        "actor" => reactor.actor_uri,
        "object" => local_note_uri(author, note),
        "content" => "🦊"
      }

      :ok = Instructions.execute(%{"action" => "save", "object" => react})
      assert Repo.get_by(Reaction, account_id: reactor.id, note_id: note.id, emoji: "🦊")

      assert :ok =
               Instructions.execute(%{
                 "action" => "save",
                 "object" => %{"type" => "Undo", "actor" => reactor.actor_uri, "object" => react}
               })

      refute Repo.get_by(Reaction, account_id: reactor.id, note_id: note.id, emoji: "🦊")
    end
  end

  # A local note carries no `ap_id`; its AP id is synthesized the same
  # way `NoteController` publishes it.
  defp local_note_uri(%Account{username: u}, %{id: id}) do
    "https://#{Config.domain!()}/users/#{u}/notes/#{id}"
  end

  defp create_account!(username) do
    %Account{username: username, display_name: username, summary: ""}
    |> Repo.insert!()
  end

  defp create_remote_account!(username, domain) do
    %Account{
      username: username,
      display_name: username,
      summary: "",
      domain: domain,
      actor_uri: "https://#{domain}/users/#{username}",
      inbox_url: "https://#{domain}/users/#{username}/inbox"
    }
    |> Repo.insert!()
  end
end
