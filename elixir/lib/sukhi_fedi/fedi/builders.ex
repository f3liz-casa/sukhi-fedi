# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Fedi.Builders do
  @moduledoc """
  Builds outbound ActivityPub JSON-LD from the domain payloads the
  delivery node sends to `fedify.translate.v1` — the native port of
  `bun/handlers/build/*.ts`, with the same payload contracts and the
  same result envelopes (`{"note": …, "recipientInboxes": …}` etc.).

  Order of operations is preserved from the Bun version: build the core
  activity → LD-sign it → inject the compatibility extras
  (`_misskey_content`, quote aliases, attachments). The extras land
  *after* signing, exactly as before, so receivers see byte-compatible
  semantics. (Yes, that means the LD signature does not cover them —
  a pre-existing tradeoff; direct delivery is authenticated by the
  HTTP signature.)

  The FEP-8b32 Object Integrity Proof joins in fedify's order where it
  can: proof first, LD signature over it, so Mastodon-family receivers
  (which canonicalize everything but `signature`) still verify the
  LD-sig, and fedify-family receivers (which strip `signature` and
  `proof`) verify the proof. note/dm are the exception — their extras
  land after the LD signature and the proof must cover what's actually
  delivered, so there the proof comes last and the LD signature stays
  exactly as uncovering as it already was.
  """

  alias SukhiFedi.Fedi.{Audience, JWK, LdSignature, Oip}

  # One shared @context for everything we emit. AS + security/v1 (for
  # the signature terms) + the handful of compatibility terms our
  # injected fields use, so strict JSON-LD consumers don't drop them.
  @context [
    "https://www.w3.org/ns/activitystreams",
    "https://w3id.org/security/v1",
    # Defines the `proof` member (FEP-8b32), so it expands instead of
    # being dropped — and is therefore covered by the LD signature when
    # the proof is attached before signing.
    "https://w3id.org/security/data-integrity/v1",
    %{
      "toot" => "http://joinmastodon.org/ns#",
      "misskey" => "https://misskey-hub.net/ns#",
      "sensitive" => "as:sensitive",
      "Hashtag" => "as:Hashtag",
      "Emoji" => "toot:Emoji",
      "_misskey_content" => "misskey:_misskey_content",
      "_misskey_quote" => "misskey:_misskey_quote",
      "quoteUrl" => "as:quoteUrl"
    }
  ]

  @doc """
  Dispatches a `fedify.translate.v1` request. Returns the same result
  envelope the Bun handler for that `object_type` returned.
  """
  @spec build(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  def build("note", p), do: note(p)
  def build("dm", p), do: dm(p)
  def build("follow", p), do: follow(p)
  def build("announce", p), do: announce(p)
  def build("like", p), do: like(p)
  def build("emoji_react", p), do: emoji_react(p)
  def build("undo", p), do: undo(p)
  def build("delete", p), do: delete(p)
  def build("add", p), do: collection_op("Add", p)
  def build("remove", p), do: collection_op("Remove", p)
  def build(other, _p), do: {:error, "unknown object_type: #{other}"}

  # ── Builders ─────────────────────────────────────────────────────────────

  defp note(p) do
    audience = Audience.public(p["actor"])

    object =
      %{
        "id" => p["noteId"],
        "type" => "Note",
        "attributedTo" => p["actor"],
        "content" => p["content"],
        "published" => now(),
        "to" => audience.to,
        "cc" => audience.cc
      }
      |> put_if("inReplyTo", p["inReplyToId"])
      # The author's content warning (AP `summary`) and sensitive flag were
      # never carried before, so remotes rendered CW'd / NSFW posts unwarned.
      |> put_if("summary", p["summary"])
      |> put_if("sensitive", p["sensitive"])

    activity = wrap_create(p, object, audience)

    with {:ok, signed} <- sign(p, activity),
         injected =
           signed
           |> inject_misskey_content(p["content"])
           |> inject_quote(p["quoteUrl"])
           |> inject_attachments(p["attachments"]),
         {:ok, proved} <- attach_proof(injected, p) do
      {:ok, %{"note" => proved, "recipientInboxes" => p["recipientInboxes"]}}
    end
  end

  defp dm(p) do
    audience = Audience.direct(p["recipientActors"] || [])

    object =
      %{
        "id" => p["noteId"],
        "type" => "Note",
        "attributedTo" => p["actor"],
        "content" => p["content"],
        "published" => now(),
        "to" => audience.to,
        "cc" => audience.cc
      }
      |> put_if("inReplyTo", p["inReplyToId"])
      |> put_if("context", p["conversationId"])

    activity = wrap_create(p, object, audience)

    with {:ok, signed} <- sign(p, activity),
         injected =
           signed
           |> inject_misskey_content(p["content"])
           |> inject_attachments(p["attachments"]),
         {:ok, proved} <- attach_proof(injected, p) do
      {:ok, %{"note" => proved, "recipientInboxes" => p["recipientInboxes"]}}
    end
  end

  defp follow(p) do
    activity = %{
      "@context" => @context,
      "id" => p["activityId"],
      "type" => "Follow",
      "actor" => p["actor"],
      "object" => p["object"]
    }

    with {:ok, signed} <- sign_and_prove(p, activity) do
      {:ok, %{"follow" => signed}}
    end
  end

  defp announce(p) do
    audience = Audience.public(p["actor"])

    activity = %{
      "@context" => @context,
      "id" => p["activityId"],
      "type" => "Announce",
      "actor" => p["actor"],
      "object" => p["object"],
      "published" => now(),
      "to" => audience.to,
      "cc" => audience.cc
    }

    with {:ok, signed} <- sign_and_prove(p, activity) do
      {:ok, %{"announce" => signed, "recipientInboxes" => p["recipientInboxes"]}}
    end
  end

  defp like(p) do
    activity = %{
      "@context" => @context,
      "id" => p["activityId"],
      "type" => "Like",
      "actor" => p["actor"],
      "object" => p["object"],
      "published" => now()
    }

    with {:ok, signed} <- sign_and_prove(p, activity) do
      {:ok, %{"like" => signed, "recipientInboxes" => p["recipientInboxes"]}}
    end
  end

  # A Misskey-style emoji reaction rides as Like-with-content (recent
  # Misskey/Sharkey emit this; Mastodon reads it as a plain Like, while
  # Pleroma's EmojiReact gets quarantined there). Custom emoji attach a
  # matching `Emoji` tag with the icon URL.
  defp emoji_react(p) do
    activity =
      %{
        "@context" => @context,
        "id" => p["activityId"],
        "type" => "Like",
        "actor" => p["actor"],
        "object" => p["object"],
        "content" => p["content"],
        "published" => now()
      }
      |> put_if("tag", emoji_tag(p["tag"]))

    with {:ok, signed} <- sign_and_prove(p, activity) do
      {:ok, %{"emojiReact" => signed, "recipientInboxes" => p["recipientInboxes"]}}
    end
  end

  defp undo(p) do
    inner = p["inner"]

    audience = Audience.mirror(inner["object"])

    activity = %{
      "@context" => @context,
      "id" => p["activityId"],
      "type" => "Undo",
      "actor" => p["actor"],
      "object" => %{
        "id" => inner["id"],
        "type" => inner["type"],
        "actor" => p["actor"],
        "object" => inner["object"]
      },
      "published" => now(),
      "to" => audience.to,
      "cc" => audience.cc
    }

    with {:ok, signed} <- sign_and_prove(p, activity) do
      {:ok, %{"undo" => signed, "recipientInboxes" => p["recipientInboxes"]}}
    end
  end

  defp delete(p) do
    audience = Audience.public(p["actor"])

    activity = %{
      "@context" => @context,
      "id" => p["activityId"],
      "type" => "Delete",
      "actor" => p["actor"],
      "object" => %{"id" => p["objectId"], "type" => "Tombstone"},
      "published" => now(),
      "to" => audience.to,
      "cc" => audience.cc
    }

    with {:ok, signed} <- sign_and_prove(p, activity) do
      {:ok, %{"delete" => signed, "recipientInboxes" => p["recipientInboxes"]}}
    end
  end

  defp collection_op(type, p) do
    activity = %{
      "@context" => @context,
      "id" => p["activityId"],
      "type" => type,
      "actor" => p["actor"],
      "object" => p["objectUri"],
      "target" => p["targetUri"]
    }

    with {:ok, signed} <- sign_and_prove(p, activity) do
      {:ok, %{"activity" => signed, "recipientInboxes" => p["recipientInboxes"]}}
    end
  end

  # ── Shared pieces ────────────────────────────────────────────────────────

  defp wrap_create(p, object, audience) do
    %{
      "@context" => @context,
      "id" => p["activityId"],
      "type" => "Create",
      "actor" => p["actor"],
      "to" => audience.to,
      "cc" => audience.cc,
      "object" => object
    }
  end

  defp sign(%{"privateKeyJwk" => jwk, "keyId" => key_id}, activity) do
    with {:ok, private_key} <- JWK.private_key(jwk) do
      LdSignature.sign(activity, private_key, key_id)
    end
  end

  defp sign(_p, _activity), do: {:error, :missing_signing_key}

  # FEP-8b32 proof, attached when the payload carries the actor's
  # Ed25519 key (absent on rows the migration backfill hasn't reached,
  # or when the delivery node predates it — the RSA signatures still
  # carry the activity then). A key that is present but unreadable is
  # a real error, not a silent downgrade.
  defp attach_proof(activity, %{"ed25519PrivateKeyJwk" => jwk, "ed25519KeyId" => key_id}) do
    with {:ok, private_key} <- JWK.ed25519_private_key(jwk) do
      Oip.sign(activity, private_key, key_id)
    end
  end

  defp attach_proof(activity, _p), do: {:ok, activity}

  # fedify's order, for builders without post-sign injections: proof
  # first, LD signature over it, so both survive verification (see
  # moduledoc).
  defp sign_and_prove(p, activity) do
    with {:ok, proved} <- attach_proof(activity, p) do
      sign(p, proved)
    end
  end

  # ── Post-signature compatibility injections (parity with utils.ts) ──────

  defp inject_misskey_content(activity, content),
    do: update_object(activity, &Map.put(&1, "_misskey_content", content))

  # TODO(FEP-044f): we emit the Misskey-style aliases (`quoteUrl`,
  # `_misskey_quote`) and the FEP-e232 tag Link below, but not the
  # FEP-044f `quote` property — Mastodon treats alias-only quotes as
  # "legacy" and renders them without the inline preview, and Hollo
  # gates quoting on its interaction policy. Full support means: add
  # `"quote" => quote_uri` (+ `@context` entry
  # `{"quote": {"@id": "https://w3id.org/fep/044f#quote", "@type": "@id"}}`)
  # before signing, and handle the QuoteRequest → QuoteAuthorization
  # round trip (see the matching TODO in Fedi.Inbox).
  defp inject_quote(activity, quote_uri) when is_binary(quote_uri) and quote_uri != "" do
    update_object(activity, fn object ->
      tags = List.wrap(object["tag"] || [])

      quote_link = %{
        "type" => "Link",
        "mediaType" => ~s(application/ld+json; profile="https://www.w3.org/ns/activitystreams"),
        "href" => quote_uri,
        "name" => "RE: #{quote_uri}",
        "rel" => "https://misskey-hub.net/ns#_misskey_quote"
      }

      object
      |> Map.put("quoteUrl", quote_uri)
      |> Map.put("_misskey_quote", quote_uri)
      |> Map.put("tag", tags ++ [quote_link])
    end)
  end

  defp inject_quote(activity, _), do: activity

  defp inject_attachments(activity, [_ | _] = attachments) do
    documents =
      Enum.map(attachments, fn a ->
        %{"type" => "Document", "url" => a["url"]}
        |> put_if("mediaType", a["mediaType"])
        |> put_if("name", a["name"])
        |> put_if("blurhash", a["blurhash"])
        |> put_if("width", a["width"])
        |> put_if("height", a["height"])
      end)

    update_object(activity, &Map.put(&1, "attachment", documents))
  end

  defp inject_attachments(activity, _), do: activity

  defp update_object(%{"object" => object} = activity, fun) when is_map(object),
    do: %{activity | "object" => fun.(object)}

  defp update_object(activity, _fun), do: activity

  defp emoji_tag(%{"name" => name, "url" => url}) do
    [
      %{
        "type" => "Emoji",
        "name" => name,
        "icon" => %{"type" => "Image", "url" => url}
      }
    ]
  end

  defp emoji_tag(_), do: nil

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
