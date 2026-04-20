import { signObject } from "@fedify/fedify";
import { getOrCreateKey } from "./keys.ts";
import { cachedDocumentLoader as fetchDocumentLoader } from "./context.ts";

export async function serialize(
  obj: { toJsonLd(opts: { contextLoader: typeof fetchDocumentLoader }): Promise<unknown> },
): Promise<unknown> {
  return obj.toJsonLd({ contextLoader: fetchDocumentLoader });
}

export async function signAndSerialize(
  actorUri: string,
  obj: Parameters<typeof signObject>[0],
): Promise<unknown> {
  const documentLoader = fetchDocumentLoader;
  const { privateKey, keyId } = await getOrCreateKey(actorUri);
  const signed = await signObject(obj, privateKey, new URL(keyId), {
    documentLoader,
  });
  return signed.toJsonLd({ contextLoader: documentLoader });
}

export function injectDefined(
  obj: Record<string, unknown>,
  entries: Record<string, unknown>,
): void {
  for (const [k, v] of Object.entries(entries)) {
    if (v !== undefined) obj[k] = v;
  }
}
