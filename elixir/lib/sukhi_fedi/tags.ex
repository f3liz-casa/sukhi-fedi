# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Tags do
  @moduledoc """
  Hashtag extraction + persistence helpers.

  A "hashtag" is `#<word>` where `<word>` is one or more Unicode word
  characters. The leading `#` is stripped and the rest is lower-cased
  before storage — `#Elixir` and `#elixir` collapse to the same row.

  `upsert_for_note/2` is meant to run inside the same `Ecto.Multi` as
  the note insert: it pulls the candidate tags from the content, makes
  sure each `tags` row exists, then links them via `note_tags`.
  """

  import Ecto.Query

  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Tag

  # Word boundary on the left, `#`, then a run of Unicode word chars.
  # We don't try to be smarter than Mastodon here: no Misskey-style
  # category tags, no length-1 single-digit tags.
  @hashtag_re ~r/(?<![\w&])#([\p{L}\p{N}_]{2,100})/u

  @doc "Extract a list of normalised tag names (no `#`, lower-case, unique)."
  @spec extract(String.t() | nil) :: [String.t()]
  def extract(nil), do: []

  def extract(content) when is_binary(content) do
    Regex.scan(@hashtag_re, content, capture: :all_but_first)
    |> Enum.map(fn [t] -> String.downcase(t) end)
    |> Enum.uniq()
  end

  @doc "Idempotent upsert: returns the loaded Tag rows for every name."
  @spec upsert_all([String.t()]) :: [Tag.t()]
  def upsert_all([]), do: []

  def upsert_all(names) when is_list(names) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    rows = Enum.map(names, fn n -> %{name: n, created_at: now} end)

    {_n, _} =
      Repo.insert_all("tags", rows,
        on_conflict: :nothing,
        conflict_target: [:name]
      )

    Repo.all(from t in Tag, where: t.name in ^names)
  end

  @doc """
  Upsert tags for a note (idempotent both on tag names and on
  note_tags links). Returns the list of tag names attached.
  """
  @spec upsert_for_note(integer(), String.t() | nil) :: [String.t()]
  def upsert_for_note(note_id, content) when is_integer(note_id) do
    case extract(content) do
      [] ->
        []

      names ->
        tags = upsert_all(names)

        rows = Enum.map(tags, fn t -> %{note_id: note_id, tag_id: t.id} end)

        Repo.insert_all("note_tags", rows,
          on_conflict: :nothing,
          conflict_target: [:note_id, :tag_id]
        )

        Enum.map(tags, & &1.name)
    end
  end
end
