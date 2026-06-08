# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.List do
  use Ecto.Schema
  import Ecto.Changeset

  @replies_policies ~w(followed list none)

  schema "lists" do
    field :title, :string
    field :replies_policy, :string, default: "list"
    field :exclusive, :boolean, default: false
    # Per-list home filters (apply to members' posts in the home timeline;
    # ignored for exclusive lists, which drop members from home entirely).
    field :filter_only_media, :boolean, default: false
    field :filter_hide_boosts, :boolean, default: false
    field :filter_hide_sensitive, :boolean, default: false
    belongs_to :account, SukhiFedi.Schema.Account

    many_to_many :accounts, SukhiFedi.Schema.Account, join_through: "list_accounts"

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(list, attrs) do
    list
    |> cast(attrs, [
      :account_id,
      :title,
      :replies_policy,
      :exclusive,
      :filter_only_media,
      :filter_hide_boosts,
      :filter_hide_sensitive
    ])
    |> validate_required([:account_id, :title])
    |> validate_length(:title, min: 1, max: 100)
    |> validate_inclusion(:replies_policy, @replies_policies)
  end
end
