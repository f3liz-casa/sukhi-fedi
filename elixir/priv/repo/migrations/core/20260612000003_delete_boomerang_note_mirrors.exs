# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.DeleteBoomerangNoteMirrors do
  use Ecto.Migration

  @moduledoc """
  Delete "boomerang" note rows: our own Create activities that came
  back to our own inbox (delivery POSTs to local followers' inboxes;
  relays can bounce too) and were mirrored as if remote. They are
  recognizable by an `ap_id` on our own host whose trailing note id
  points at a *different* row — the genuine local original.

  Mirror now refuses these at ingest (`Instructions.Mirror.own_host?`);
  this migration cleans up the rows minted before that gate existed.
  Any FK refs that accumulated on a boomerang (favs, notifications, …)
  are repointed to the original before the delete, using the same
  catalog-driven ref list as `Maintenance.RebuildRemoteNoteIds`. A dup
  whose original vanished, or whose refs cannot move, is left in place
  rather than failing boot.
  """

  def up do
    domain = System.get_env("DOMAIN")

    if is_binary(domain) and domain != "" do
      refs = note_fk_refs()
      pattern = "^https://" <> String.replace(domain, ".", "\\.") <> "/users/[^/]+/notes/[0-9]+$"

      %{rows: dups} =
        repo().query!(
          """
          SELECT r.id, (regexp_match(r.ap_id, '/notes/([0-9]+)$'))[1]::bigint
          FROM notes r
          WHERE r.ap_id ~ $1
            AND (regexp_match(r.ap_id, '/notes/([0-9]+)$'))[1]::bigint <> r.id
          """,
          [pattern]
        )

      for [dup_id, orig_id] <- dups do
        %{rows: orig} = repo().query!("SELECT 1 FROM notes WHERE id = $1", [orig_id])

        if orig != [] do
          try do
            for {table, column} <- refs do
              repo().query!(
                "UPDATE #{quote_ident(table)} SET #{quote_ident(column)} = $1 " <>
                  "WHERE #{quote_ident(column)} = $2",
                [orig_id, dup_id]
              )
            end

            repo().query!("DELETE FROM notes WHERE id = $1", [dup_id])
          rescue
            e ->
              IO.puts(
                "boomerang cleanup: leaving note #{dup_id} in place (#{Exception.message(e)})"
              )
          end
        end
      end
    end
  end

  def down, do: :ok

  defp note_fk_refs do
    sql = """
    SELECT tc.table_name, kcu.column_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name
     AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage ccu
      ON tc.constraint_name = ccu.constraint_name
     AND tc.table_schema = ccu.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND ccu.table_name = 'notes'
      AND ccu.column_name = 'id'
    """

    repo().query!(sql).rows |> Enum.map(fn [table, column] -> {table, column} end)
  end

  defp quote_ident(name), do: ~s("#{String.replace(name, "\"", "\"\"")}")
end
