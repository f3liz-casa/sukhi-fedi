# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Nats.Helpers do
  @moduledoc """
  Shared helpers for the `SukhiFedi.Nats.*` topic modules:
  response envelope construction, int parsing, and per-entity serializers.
  """

  def ok_resp(data), do: %{ok: true, data: data}
  def error_resp(error), do: %{ok: false, error: error}

  def parse_int(nil, default), do: default

  def parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      _ -> default
    end
  end

  def parse_int(int, _default) when is_integer(int), do: int
  def parse_int(_, default), do: default

  def serialize_account(account) do
    %{
      id: account.id,
      username: account.username,
      display_name: account.display_name,
      bio: account.bio,
      avatar_url: account.avatar_url,
      banner_url: account.banner_url,
      created_at: account.inserted_at
    }
  end

  def serialize_article(article) do
    %{
      id: article.id,
      title: article.title,
      content: article.content,
      summary: article.summary,
      published_at: article.published_at,
      account_id: article.account_id
    }
  end

  def serialize_media(media) do
    %{
      id: media.id,
      url: media.url,
      thumbnail_url: media.thumbnail_url,
      mime_type: media.mime_type,
      blurhash: media.blurhash,
      description: media.description,
      sensitive: media.sensitive
    }
  end

  def serialize_note(note) do
    %{
      id: note.id,
      content: note.content,
      visibility: note.visibility,
      cw: note.cw,
      mfm: note.mfm,
      created_at: note.created_at,
      account_id: note.account_id,
      in_reply_to_ap_id: note.in_reply_to_ap_id,
      conversation_ap_id: note.conversation_ap_id,
      quote_of_ap_id: note.quote_of_ap_id
    }
  end

  @doc """
  Best-effort inbox URI for an actor URI. Real implementations should
  fetch the actor profile via `SukhiFedi.Federation.ActorFetcher.fetch/1`
  instead.
  """
  def derive_inbox_uri(actor_uri), do: "#{actor_uri}/inbox"
end
