# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.AP.Instructions.Extract do
  @moduledoc """
  Pure extractors over inbound AP JSON — no DB, no network. Every
  handler module reads activity shapes through these so the quirks
  (fedify inlining actors, Misskey quote fields, MFM side channels)
  are named in one place.
  """

  @public_ns "https://www.w3.org/ns/activitystreams#Public"
  @as_public "Public"

  # fedify's `follow.toJsonLd({ contextLoader })` inlines the resolved
  # actor object (full Person JSON-LD) into the `actor` field instead of
  # leaving it as a bare ID string. Accept both shapes.
  def extract_uri(uri) when is_binary(uri), do: uri
  def extract_uri(%{"id" => id}) when is_binary(id), do: id
  def extract_uri(%{"@id" => id}) when is_binary(id), do: id
  def extract_uri(_), do: nil

  def extract_object_id(id) when is_binary(id), do: id
  def extract_object_id(%{"id" => id}) when is_binary(id), do: id
  def extract_object_id(_), do: nil

  @doc """
  True when two AP id/uri values (string or inlined `%{"id" => …}`) share
  the same host. Case-insensitive; false if either host is missing.
  """
  def same_host?(a, b) do
    with ua when is_binary(ua) <- extract_uri(a),
         ub when is_binary(ub) <- extract_uri(b),
         %URI{host: ha} when is_binary(ha) and ha != "" <- URI.parse(ua),
         %URI{host: hb} when is_binary(hb) and hb != "" <- URI.parse(ub) do
      String.downcase(ha) == String.downcase(hb)
    else
      _ -> false
    end
  end

  # Misskey and its forks signal a quote-note with one of several
  # top-level fields on the Object; FEP-e232 servers instead put it in a
  # `tag` Link. Accept all of them.
  def extract_quote_uri(note) when is_map(note) do
    extract_uri(note["quoteUrl"]) ||
      extract_uri(note["quoteUri"]) ||
      extract_uri(note["_misskey_quote"]) ||
      quote_uri_from_tag(note["tag"])
  end

  def extract_quote_uri(_), do: nil

  # FEP-e232: the quote travels as a `tag` entry of type `Link` whose
  # `rel` marks it a quote (Misskey's `_misskey_quote` rel or the
  # FEP-e232 rel). Return the first matching `href`.
  defp quote_uri_from_tag(tags) when is_list(tags) do
    Enum.find_value(tags, fn
      %{"type" => "Link"} = link ->
        if quote_rel?(link["rel"]), do: extract_uri(link["href"]), else: nil

      _ ->
        nil
    end)
  end

  defp quote_uri_from_tag(_), do: nil

  defp quote_rel?(rel) when is_binary(rel), do: quote_rel_match?(rel)
  defp quote_rel?(rels) when is_list(rels), do: Enum.any?(rels, &quote_rel_match?/1)
  defp quote_rel?(_), do: false

  defp quote_rel_match?(rel) when is_binary(rel) do
    String.contains?(rel, "_misskey_quote") or String.contains?(rel, "e232")
  end

  defp quote_rel_match?(_), do: false

  # MFM (Misskey Flavored Markdown) source travels out of band of the
  # rendered `content` — as `_misskey_content` or a `source` object.
  # Keep it so the source round-trips instead of collapsing to HTML.
  def extract_mfm(note) when is_map(note) do
    case note["_misskey_content"] do
      s when is_binary(s) and s != "" -> s
      _ -> mfm_from_source(note["source"])
    end
  end

  def extract_mfm(_), do: nil

  defp mfm_from_source(%{"content" => s}) when is_binary(s) and s != "", do: s
  defp mfm_from_source(_), do: nil

  # The content warning rides the AP `summary`. Mirror it so the Mastodon
  # view hides the body behind a spoiler (cw drives `spoiler_text` and
  # `sensitive`).
  def content_warning(%{"summary" => s}) when is_binary(s) and s != "", do: s
  def content_warning(_), do: nil

  def normalize_collection(list) when is_list(list), do: list
  def normalize_collection(str) when is_binary(str), do: [str]
  def normalize_collection(_), do: []

  def public?(uri) when is_binary(uri), do: uri == @public_ns or uri == @as_public
  def public?(_), do: false

  @doc """
  AS#Public in to/cc ⇒ not a DM. We treat absence-of-public as the DM
  signal (matches the DM handler's heuristic).
  """
  def dm_addressing?(note) do
    to = normalize_collection(note["to"] || [])
    cc = normalize_collection(note["cc"] || [])
    audience = to ++ cc

    audience != [] and
      Enum.all?(audience, fn r -> not public?(r) end)
  end

  def visibility_from(note) do
    to = normalize_collection(note["to"] || [])
    cc = normalize_collection(note["cc"] || [])

    public_in_to = Enum.any?(to, &public?/1)
    public_in_cc = Enum.any?(cc, &public?/1)
    has_followers_addr = Enum.any?(to ++ cc, &String.ends_with?(&1 || "", "/followers"))

    cond do
      public_in_to -> "public"
      public_in_cc -> "unlisted"
      has_followers_addr -> "followers"
      true -> "direct"
    end
  end

  # The trailing path segment of a local actor URI is its username
  # (`https://host/users/<name>`). Raises on a path-less URI, which a
  # well-formed actor URI never is.
  def actor_username(uri) do
    uri |> URI.parse() |> Map.get(:path, "") |> String.split("/") |> List.last()
  end

  def actor_host(actor_uri) do
    case URI.parse(actor_uri) do
      %URI{host: h} when is_binary(h) -> h
      _ -> nil
    end
  end
end
