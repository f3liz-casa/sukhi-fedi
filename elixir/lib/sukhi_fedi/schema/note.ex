# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.Note do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notes" do
    field(:content, :string)
    # An Article's human title (AP `name`); NULL for a plain Note. Kept
    # structured alongside the `<h2>` we also fold into `content`, so the
    # client can detect an article and route it to its reader page.
    field(:title, :string)
    field(:visibility, :string, default: "public")
    field(:ap_id, :string)
    field(:cw, :string)
    field(:sensitive, :boolean, default: false)
    field(:in_reply_to_ap_id, :string)
    field(:conversation_ap_id, :string)
    field(:quote_of_ap_id, :string)
    field(:mfm, :string)
    field(:emojis, {:array, :map}, default: [])

    # Virtual, populated by `Notes.with_refs/1` for the Mastodon view:
    # the reply parent resolved to a local row, and the quoted note (with
    # its account preloaded) for a nested-Status `quote` render.
    field(:in_reply_to_id, :integer, virtual: true)
    field(:in_reply_to_account_id, :integer, virtual: true)
    field(:quoted_note, :map, virtual: true)
    # Virtual, populated by `Notes.with_refs/2` when the note owns a poll:
    # the `Polls.get_with_results/2` map, ready for `MastodonPoll.render/1`.
    field(:poll_view, :map, virtual: true)

    belongs_to(:account, SukhiFedi.Schema.Account)
    many_to_many(:media, SukhiFedi.Schema.Media, join_through: "note_media")
    many_to_many(:tags, SukhiFedi.Schema.Tag, join_through: "note_tags")
    has_one(:poll, SukhiFedi.Schema.Poll)
    has_many(:reactions, SukhiFedi.Schema.Reaction)

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [
      :content,
      :title,
      :visibility,
      :account_id,
      :cw,
      :sensitive,
      :ap_id,
      :in_reply_to_ap_id,
      :conversation_ap_id,
      :quote_of_ap_id,
      :mfm,
      :emojis
    ])
    |> update_change(:content, &SukhiFedi.HTML.sanitize/1)
    |> validate_required([:content, :account_id])
    # Cap content length (the only schema field that lacked one): bounds
    # unbounded storage + tag-row amplification from a multi-MB local post
    # or federated note. Oversized federated inserts simply fail the
    # changeset and are dropped. The ceiling is generous enough to hold a
    # hackers.pub `Article` (long-form HTML, title folded in) — a 5 000-char
    # cap silently dropped those — while still bounding multi-MB abuse.
    |> validate_length(:content, max: 100_000)
    |> validate_inclusion(:visibility, ["public", "followers", "direct"])
  end
end
