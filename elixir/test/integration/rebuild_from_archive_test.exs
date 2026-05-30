# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Integration.RebuildFromArchiveTest do
  use SukhiFedi.IntegrationCase, async: false

  @moduletag :integration

  alias SukhiFedi.Maintenance.RebuildFromArchive
  alias SukhiFedi.Schema.{Account, Note}

  describe "rebuild_note/2" do
    test "backfills cw and created_at from the archived note object" do
      ap_id = "https://remote.example/notes/arch-1"
      note = insert_remote_note(ap_id, cw: nil, created_at: ~U[2026-05-30 06:00:00Z])

      obj = %{
        "id" => ap_id,
        "summary" => "CW: spoilers",
        "published" => "2021-01-02T03:04:05Z"
      }

      assert :updated = RebuildFromArchive.rebuild_note(obj, :execute)

      reloaded = Repo.get!(Note, note.id)
      assert reloaded.cw == "CW: spoilers"
      assert DateTime.compare(reloaded.created_at, ~U[2021-01-02 03:04:05Z]) == :eq
    end

    test "dry_run reports would_update without writing" do
      ap_id = "https://remote.example/notes/arch-2"
      note = insert_remote_note(ap_id, cw: nil, created_at: ~U[2026-05-30 06:00:00Z])

      obj = %{"id" => ap_id, "summary" => "CW", "published" => "2021-01-02T03:04:05Z"}

      assert :would_update = RebuildFromArchive.rebuild_note(obj, :dry_run)

      # untouched
      reloaded = Repo.get!(Note, note.id)
      assert reloaded.cw == nil
      assert DateTime.compare(reloaded.created_at, ~U[2026-05-30 06:00:00Z]) == :eq
    end

    test "no change when the archive adds nothing new" do
      ap_id = "https://remote.example/notes/arch-3"
      insert_remote_note(ap_id, cw: "CW: kept", created_at: ~U[2021-01-02 03:04:05Z])

      # same cw, same published, and an absent summary must not clear cw
      obj = %{"id" => ap_id, "summary" => "CW: kept", "published" => "2021-01-02T03:04:05Z"}
      assert :unchanged = RebuildFromArchive.rebuild_note(obj, :execute)

      obj_no_summary = %{"id" => ap_id, "published" => "2021-01-02T03:04:05Z"}
      assert :unchanged = RebuildFromArchive.rebuild_note(obj_no_summary, :execute)
    end

    test "never clears an existing cw the archive omits" do
      ap_id = "https://remote.example/notes/arch-4"
      note = insert_remote_note(ap_id, cw: "CW: keep me", created_at: ~U[2021-01-02 03:04:05Z])

      assert :unchanged =
               RebuildFromArchive.rebuild_note(%{"id" => ap_id, "published" => "2021-01-02T03:04:05Z"}, :execute)

      assert Repo.get!(Note, note.id).cw == "CW: keep me"
    end

    test "no_local_note when the ap_id is unknown" do
      assert :no_local_note =
               RebuildFromArchive.rebuild_note(%{"id" => "https://remote.example/notes/ghost"}, :execute)
    end
  end

  defp insert_remote_note(ap_id, opts) do
    author =
      Repo.insert!(%Account{
        username: "arch_#{System.unique_integer([:positive])}",
        display_name: "arch",
        summary: "",
        domain: "remote.example",
        actor_uri: "https://remote.example/users/arch"
      })

    Repo.insert!(%Note{
      account_id: author.id,
      content: "body",
      visibility: "public",
      ap_id: ap_id,
      cw: opts[:cw],
      created_at: opts[:created_at]
    })
  end
end
