# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.NoteDraft do
  use Ecto.Schema
  import Ecto.Changeset

  # A compose draft — the server-side, cross-device twin of the SPA's
  # local `sf.compose_draft`. One row per account (unique index on
  # `account_id`), holding only the small text fields the composer
  # restores. Never federated, never published from here; pruned when the
  # note is posted. The visibility set is the composer's, not the Note's
  # stored set — a draft echoes what the box holds, and the post path maps
  # it.
  schema "notes_drafts" do
    field :account_id, :integer
    field :text, :string, default: ""
    field :spoiler, :string, default: ""
    field :sensitive, :boolean, default: false
    field :visibility, :string, default: "public"
    timestamps()
  end

  @visibilities ~w(public unlisted private direct)

  def changeset(draft, attrs) do
    draft
    |> cast(attrs, [:account_id, :text, :spoiler, :sensitive, :visibility])
    |> validate_required([:account_id])
    |> validate_inclusion(:visibility, @visibilities)
  end
end
