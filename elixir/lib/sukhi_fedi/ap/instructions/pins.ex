# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.AP.Instructions.Pins do
  @moduledoc """
  Inbound `Add` / `Remove` targeting a featured collection — a local
  actor's pinned/unpinned posts arriving over the inbox.
  """

  alias SukhiFedi.Addons.PinnedNotes
  alias SukhiFedi.AP.Instructions.Extract
  alias SukhiFedi.Repo

  @doc "Handle Add/Remove targeting a featured collection (pinned/unpinned posts)."
  def maybe_handle_pin_unpin(%{
        "type" => "Add",
        "actor" => actor_uri,
        "object" => note_uri,
        "target" => target_uri
      })
      when is_binary(actor_uri) and is_binary(note_uri) and is_binary(target_uri) do
    domain = SukhiFedi.Config.domain!()
    username = Extract.actor_username(actor_uri)

    account =
      if String.contains?(actor_uri, domain),
        do: SukhiFedi.Accounts.by_local_username(username),
        else: nil

    if account && String.ends_with?(target_uri, "/featured") do
      note = Repo.get_by(SukhiFedi.Schema.Note, ap_id: note_uri)
      if note, do: PinnedNotes.pin(account.id, note.id)
    end
  end

  def maybe_handle_pin_unpin(%{
        "type" => "Remove",
        "actor" => actor_uri,
        "object" => note_uri,
        "target" => target_uri
      })
      when is_binary(actor_uri) and is_binary(note_uri) and is_binary(target_uri) do
    domain = SukhiFedi.Config.domain!()
    username = Extract.actor_username(actor_uri)

    account =
      if String.contains?(actor_uri, domain),
        do: SukhiFedi.Accounts.by_local_username(username),
        else: nil

    if account && String.ends_with?(target_uri, "/featured") do
      note = Repo.get_by(SukhiFedi.Schema.Note, ap_id: note_uri)
      if note, do: PinnedNotes.unpin(account.id, note.id)
    end
  end

  def maybe_handle_pin_unpin(_), do: :ok
end
