# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Integration.MirrorBoomerangTest do
  @moduledoc """
  Our own Create comes back to our inbox whenever a local user has
  local followers (delivery POSTs to their inboxes) or a relay
  forwards our post. The mirror must refuse to mint a second row for
  a note whose id lives on our own host — the real row already exists
  with `ap_id` NULL, so the ap_id unique index cannot catch this.
  """

  use SukhiFedi.IntegrationCase, async: false

  @moduletag :integration

  import Ecto.Query

  alias SukhiFedi.AP.Instructions.Mirror
  alias SukhiFedi.Notes
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Account, Note}

  test "our own Create delivered back to our inbox does not mint a second row" do
    alice = create_account!("boomerang_alice")

    {:ok, note} =
      Notes.create_status(alice, %{"status" => "boomerang", "visibility" => "public"})

    domain = SukhiFedi.Config.domain!()
    actor = "https://#{domain}/users/#{alice.username}"
    canonical = "#{actor}/notes/#{note.id}"

    activity = %{
      "type" => "Create",
      "actor" => actor,
      "object" => %{
        "type" => "Note",
        "id" => canonical,
        "attributedTo" => actor,
        "content" => "<p>boomerang</p>",
        "to" => ["https://www.w3.org/ns/activitystreams#Public"]
      }
    }

    count_before = Repo.aggregate(Note, :count, :id)

    assert :ok = Mirror.maybe_mirror_create_note(activity)

    assert Repo.aggregate(Note, :count, :id) == count_before
    assert [] = Repo.all(from(n in Note, where: n.ap_id == ^canonical))
  end

  defp create_account!(username) do
    %Account{username: username, display_name: username, summary: ""}
    |> Repo.insert!()
  end
end
