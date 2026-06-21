# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddQuoteAuthorizations do
  use Ecto.Migration

  @moduledoc """
  FEP-044f quote approval.

  When a remote actor quotes one of our public notes it sends a
  `QuoteRequest`; we auto-approve and mint a dereferenceable
  `QuoteAuthorization` the requester embeds as proof. One row per granted
  authorization, served at `/users/<u>/quote-auth/<id>`:

    * `note_id`                — the local note being quoted (interactionTarget)
    * `requester_actor_uri`    — the remote actor who asked to quote it
    * `interacting_object_uri` — the remote quote post (interactingObject)

  The notes side gets `quote_authorization_ap_id`: the stamp a *remote*
  author granted us when we quoted their post. We echo it on our outbound
  note so third parties can verify the quote inline.
  """

  def change do
    create table(:quote_authorizations) do
      add :note_id, references(:notes, on_delete: :delete_all), null: false
      add :requester_actor_uri, :string, null: false
      add :interacting_object_uri, :string, null: false
      add :state, :string, null: false, default: "approved"
      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    # A re-sent QuoteRequest reuses the same stamp instead of minting a
    # new one.
    create unique_index(:quote_authorizations, [:note_id, :interacting_object_uri])

    alter table(:notes) do
      add :quote_authorization_ap_id, :string
    end
  end
end
