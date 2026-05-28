# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.CustomEmojis do
  @moduledoc """
  Custom emoji directory. Inbound `EmojiReact` / `Like+content` carrying
  a `:shortcode:` arrives with a `tag` Emoji entry; `upsert_from_tag/3`
  files it here keyed by `(shortcode, domain)` so subsequent reaction
  renders can hand the icon URL to the UI without re-parsing.

  Storage convention: `Reaction.emoji` is the **namespaced** shortcode
  for remote emoji — `:blobcat@misskey.io:` — so identical shortcodes
  from different origins stay distinct. Local emoji stay `:blobcat:`.
  """

  import Ecto.Query

  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.CustomEmoji

  @doc """
  Build the namespaced storage key for a reaction emoji.

  - Unicode glyphs are returned untouched.
  - Local `:shortcode:` (no domain) is returned untouched.
  - Remote `:shortcode:` becomes `:shortcode@host:`.
  """
  @spec namespaced(String.t(), String.t() | nil) :: String.t()
  def namespaced(emoji, nil), do: emoji
  def namespaced(emoji, ""), do: emoji

  def namespaced(emoji, domain) when is_binary(emoji) and is_binary(domain) do
    case Regex.run(~r/^:([^:@]+):$/, emoji) do
      [_, shortcode] -> ":#{shortcode}@#{domain}:"
      _ -> emoji
    end
  end

  @doc """
  Decompose a stored emoji string back into `{shortcode, domain}` for
  DB lookup. Unicode and bare shortcodes return `nil` for domain.
  Returns `nil` for non-shortcode strings (unicode glyphs).
  """
  @spec split(String.t()) :: {String.t(), String.t() | nil} | nil
  def split(emoji) when is_binary(emoji) do
    case Regex.run(~r/^:([^:@]+)(?:@([^:]+))?:$/, emoji) do
      [_, shortcode] -> {shortcode, nil}
      [_, shortcode, domain] -> {shortcode, domain}
      _ -> nil
    end
  end

  @doc """
  Upsert a remote custom emoji parsed from an activity's `tag` array.
  `tag` is the raw map (`%{"type" => "Emoji", "name" => ":foo:",
  "icon" => %{"url" => ...}}`). Returns `:ok` (idempotent).
  """
  @spec upsert_from_tag(String.t(), map(), String.t()) :: :ok
  def upsert_from_tag(shortcode, %{} = tag, domain)
      when is_binary(shortcode) and is_binary(domain) do
    icon = tag["icon"] || %{}
    url = icon["url"] || tag["url"]

    if is_binary(url) and url != "" do
      static_url =
        case icon do
          %{"summary" => s} when is_binary(s) -> s
          _ -> nil
        end

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        shortcode: shortcode,
        domain: domain,
        image_url: url,
        static_url: static_url,
        last_fetched_at: now
      }

      %CustomEmoji{}
      |> CustomEmoji.changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace, [:image_url, :static_url, :last_fetched_at]},
        conflict_target: [:shortcode, :domain]
      )
    end

    :ok
  end

  def upsert_from_tag(_shortcode, _tag, _domain), do: :ok

  @doc """
  Local custom emoji directory, in stable shortcode order. Used by
  `GET /api/v1/custom_emojis` and the reaction picker.
  """
  @spec list_local() :: [%CustomEmoji{}]
  def list_local do
    from(e in CustomEmoji,
      where: is_nil(e.domain),
      order_by: [asc: e.shortcode]
    )
    |> Repo.all()
  end

  @doc """
  Bulk-resolve a list of reaction emoji strings to a map of
  `emoji_key => %{url, static_url}`. Unicode glyphs and unknown
  shortcodes are absent from the result map.
  """
  @spec lookup_many([String.t()]) :: %{String.t() => %{url: String.t(), static_url: String.t() | nil}}
  def lookup_many([]), do: %{}

  def lookup_many(emojis) when is_list(emojis) do
    pairs =
      emojis
      |> Enum.map(&{&1, split(&1)})
      |> Enum.reject(fn {_, parsed} -> is_nil(parsed) end)

    if pairs == [] do
      %{}
    else
      shortcodes = pairs |> Enum.map(fn {_, {sc, _}} -> sc end) |> Enum.uniq()

      rows =
        from(e in CustomEmoji,
          where: e.shortcode in ^shortcodes,
          select: {e.shortcode, e.domain, e.image_url, e.static_url}
        )
        |> Repo.all()

      by_key =
        Map.new(rows, fn {sc, d, url, static_url} ->
          {{sc, d}, %{url: url, static_url: static_url}}
        end)

      pairs
      |> Enum.map(fn {emoji_key, {sc, d}} ->
        {emoji_key, Map.get(by_key, {sc, d})}
      end)
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()
    end
  end
end
