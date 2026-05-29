import { signJsonLd } from "@fedify/fedify";
import { cachedDocumentLoader as fetchDocumentLoader } from "./context.ts";
import { getImportedPrivateKey, type JwkInput } from "./key_cache.ts";

export async function serialize(
  obj: { toJsonLd(opts: { contextLoader: typeof fetchDocumentLoader }): Promise<unknown> },
): Promise<unknown> {
  return obj.toJsonLd({ contextLoader: fetchDocumentLoader });
}

// Sign an outbound Activity with RsaSignature2017 (legacy LD-Signatures)
// using the actor's published RSA key. Earlier this function used
// `signObject` from fedify v2, which only accepts Ed25519 keys — bun
// silently generated an in-memory Ed25519 keypair for it, but the
// `verificationMethod` in the proof pointed at `<actor>#main-key`,
// which resolves to the *RSA* publicKeyPem in our actor JSON. Peers
// (hackers.pub among them) then failed to verify the Ed25519 signature
// against the RSA key and rejected the activity. signJsonLd produces a
// proof whose key actually matches what we publish.
export interface SignedPayload {
  privateKeyJwk: JwkInput;
  keyId: string;
}

export async function signAndSerialize(
  creds: SignedPayload,
  obj: {
    toJsonLd(opts: { contextLoader: typeof fetchDocumentLoader }): Promise<unknown>;
  },
): Promise<unknown> {
  const jsonLd = await obj.toJsonLd({ contextLoader: fetchDocumentLoader });
  const privateKey = await getImportedPrivateKey(creds.privateKeyJwk);
  return await signJsonLd(jsonLd, privateKey, new URL(creds.keyId), {
    contextLoader: fetchDocumentLoader,
  });
}

export function injectDefined(
  obj: Record<string, unknown>,
  entries: Record<string, unknown>,
): void {
  for (const [k, v] of Object.entries(entries)) {
    if (v !== undefined) obj[k] = v;
  }
}

export function injectMisskey(activityJson: unknown, content: string): void {
  if (
    activityJson && typeof activityJson === "object" &&
    "object" in activityJson
  ) {
    const obj = (activityJson as Record<string, unknown>).object;
    if (obj && typeof obj === "object") {
      injectDefined(obj as Record<string, unknown>, {
        _misskey_content: content,
      });
    }
  }
}

// Tag a Create(Note)'s inner object as a quote-note. We emit all three
// shapes so the widest set of peers picks it up: Misskey's
// `_misskey_quote`, the cross-fork `quoteUrl`, and the FEP-e232 `tag`
// Link (Mastodon's quote-post path). No-op when there is no quote.
export function injectQuote(
  activityJson: unknown,
  quoteUri: string | null | undefined,
): void {
  if (!quoteUri) return;
  if (
    activityJson && typeof activityJson === "object" &&
    "object" in activityJson
  ) {
    const obj = (activityJson as Record<string, unknown>).object;
    if (obj && typeof obj === "object") {
      const o = obj as Record<string, unknown>;
      injectDefined(o, {
        quoteUrl: quoteUri,
        _misskey_quote: quoteUri,
      });

      // FEP-e232: append a quote Link to `tag`, preserving any existing
      // tags (mentions, hashtags, emoji).
      const tags = Array.isArray(o.tag) ? o.tag : o.tag ? [o.tag] : [];
      tags.push({
        type: "Link",
        mediaType: 'application/ld+json; profile="https://www.w3.org/ns/activitystreams"',
        href: quoteUri,
        name: `RE: ${quoteUri}`,
        rel: "https://misskey-hub.net/ns#_misskey_quote",
      });
      o.tag = tags;
    }
  }
}
