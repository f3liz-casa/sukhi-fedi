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

// Tag a Create(Note)'s inner object as a quote-note. Misskey reads
// `_misskey_quote`; `quoteUrl` is the field honoured across Misskey
// forks. (FEP-e232 `tag` Link form is not emitted.) No-op when there
// is no quote.
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
      injectDefined(obj as Record<string, unknown>, {
        quoteUrl: quoteUri,
        _misskey_quote: quoteUri,
      });
    }
  }
}
