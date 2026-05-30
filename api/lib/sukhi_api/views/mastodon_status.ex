# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Views.MastodonStatus do
  @moduledoc """
  Render a `Note` (or hydrated map) into Mastodon Status JSON.

  Counts and viewer-context flags are passed in via the second
  argument:

      MastodonStatus.render(note, %{
        counts: %{replies: int, reblogs: int, favourites: int},
        viewer: %{favourited: bool, reblogged: bool, bookmarked: bool, pinned: bool},
        reactions: [%{name: "🦊", count: 3, me: false}, ...]
      })

  All keys are optional; missing fields default to `0` / `false` / `[]`.
  Capabilities should batch-fetch via
  `SukhiFedi.Notes.{counts_for_notes, viewer_flags_many,
  reactions_for_notes}` and pass the per-note submap on render.
  """

  alias SukhiApi.Views.{Id, MastodonAccount, MastodonMedia}

  @spec render(map() | nil, map()) :: map() | nil
  def render(note, ctx \\ %{})
  def render(nil, _ctx), do: nil

  def render(note, ctx) do
    counts = Map.get(ctx, :counts, %{})
    viewer = Map.get(ctx, :viewer, %{})

    # Mastodon spec の `uri` は「常に文字列」。Moshidon など
    # Kotlin/Gson クライアントは non-null String で受けるので、
    # `ap_id` が未設定だった瞬間に NPE で落ちる。ローカル発の
    # note には `https://<domain>/users/<user>/notes/<id>` を
    # 推測フォールバックとして組み立てる。
    uri = Map.get(note, :ap_id) || derived_uri(note)

    %{
      id: Id.encode(note.id),
      created_at: format_dt(Map.get(note, :created_at)),
      in_reply_to_id: encode_id(Map.get(note, :in_reply_to_id)),
      in_reply_to_account_id: encode_id(Map.get(note, :in_reply_to_account_id)),
      sensitive: !!(Map.get(note, :cw) && Map.get(note, :cw) != ""),
      spoiler_text: Map.get(note, :cw) || "",
      visibility: Map.get(note, :visibility) || "public",
      language: nil,
      uri: uri,
      url: uri,
      replies_count: Map.get(counts, :replies, 0),
      reblogs_count: Map.get(counts, :reblogs, 0),
      favourites_count: Map.get(counts, :favourites, 0),
      edited_at: nil,
      content: render_content(note),
      reblog: nil,
      # Quote post (Fedibird-compatible): the quoted status nested one
      # level deep. nil when there's no quote or we don't hold the quoted
      # note locally yet.
      quote: render_quote(note),
      application: nil,
      account: render_account(note),
      media_attachments: render_media(note),
      mentions: [],
      tags: render_tags(note),
      emojis: Map.get(note, :emojis) || [],
      card: nil,
      poll: nil,
      pinned: Map.get(viewer, :pinned, false),
      bookmarked: Map.get(viewer, :bookmarked, false),
      favourited: Map.get(viewer, :favourited, false),
      reblogged: Map.get(viewer, :reblogged, false),
      muted: false,
      # Sukhi extension. Pleroma-compatible shape: list of
      # %{name, count, me, url, static_url}. Mastodon clients ignore
      # the unknown key; Sukhi web reads it for reaction chips.
      reactions: Map.get(ctx, :reactions, [])
    }
  end

  @doc """
  Render a list of notes, looking up per-note counts/viewer-flags
  from the supplied maps (each keyed by note id).
  """
  @spec render_list([map()], map(), map(), map()) :: [map()]
  def render_list(notes, counts_by_id \\ %{}, viewer_by_id \\ %{}, reactions_by_id \\ %{})
      when is_list(notes) do
    Enum.map(notes, fn n ->
      render(n, %{
        counts: Map.get(counts_by_id, n.id, %{}),
        viewer: Map.get(viewer_by_id, n.id, %{}),
        reactions: Map.get(reactions_by_id, n.id, [])
      })
    end)
  end

  defp encode_id(nil), do: nil
  defp encode_id(id), do: Id.encode(id)

  # The quoted status, rendered one level deep. The quoted note carries
  # no `:quoted_note` of its own (gateway only enriches the top level),
  # so the nested render's own `quote` resolves to nil — no recursion.
  defp render_quote(note) do
    case Map.get(note, :quoted_note) do
      %{} = quoted -> if Map.get(quoted, :id), do: render(quoted, %{}), else: nil
      _ -> nil
    end
  end

  defp render_content(note) do
    raw = Map.get(note, :content) || ""
    if String.starts_with?(raw, "<"), do: raw, else: "<p>#{raw}</p>"
  end

  defp render_account(note) do
    account = Map.get(note, :account)

    if is_map(account) and Map.has_key?(account, :username) do
      MastodonAccount.render(account, %{})
    else
      # spec 上 `account` も非 null。ハイドレートし忘れた経路から
      # うっかり nil が漏れると、Moshidon など Kotlin/Gson 系で
      # NPE になる。username 不明でも plausible な形を返して
      # クラッシュさせない。 [[mastodon_account.render の空 fallback と対]]
      MastodonAccount.render(
        %{id: Map.get(note, :account_id) || 0, username: "unknown"},
        %{}
      )
    end
  end

  defp render_media(note) do
    case Map.get(note, :media) do
      media when is_list(media) -> Enum.map(media, &MastodonMedia.render/1)
      _ -> []
    end
  end

  defp render_tags(note) do
    domain = SukhiApi.Config.domain!()

    case Map.get(note, :tags) do
      tags when is_list(tags) ->
        Enum.map(tags, fn t ->
          %{name: t.name, url: "https://#{domain}/tags/#{t.name}"}
        end)

      _ ->
        []
    end
  end

  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(_), do: nil

  # ap_id が落ちているときの最後の砦。account がぶら下がっていれば
  # そこから username を拾って `users/<u>/notes/<id>` を組む。それも
  # 無ければ `notes/<id>` だけでも返す ─ 形式が崩れていても non-null
  # の文字列であることが優先。
  defp derived_uri(note) do
    domain = SukhiApi.Config.domain!()
    id = Map.get(note, :id)

    case Map.get(note, :account) do
      %{username: u} when is_binary(u) ->
        "https://#{domain}/users/#{u}/notes/#{id}"

      _ ->
        "https://#{domain}/notes/#{id}"
    end
  end
end
