# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.QuoteAuthorization do
  @moduledoc """
  A FEP-044f `QuoteAuthorization` we granted: proof that a remote actor
  may quote one of our local notes.

  Minted when we auto-approve an inbound `QuoteRequest`, then served as a
  dereferenceable object at `/users/<u>/quote-auth/<id>` so the quoter —
  and any third party rendering their quote — can verify it. The
  `attributedTo` (our note's author) and `interactionTarget` (the note's
  AP id) are derived from `note_id` at serve time, not stored.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "quote_authorizations" do
    belongs_to :note, SukhiFedi.Schema.Note
    field :requester_actor_uri, :string
    field :interacting_object_uri, :string
    field :state, :string, default: "approved"

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  def changeset(auth, attrs) do
    auth
    |> cast(attrs, [:note_id, :requester_actor_uri, :interacting_object_uri, :state])
    |> validate_required([:note_id, :requester_actor_uri, :interacting_object_uri])
    |> unique_constraint([:note_id, :interacting_object_uri])
  end
end
