// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Signed AP document fetch. Mastodon Secure Mode and Misskey
// auth-fetch-required peers answer unauthenticated GETs with 401;
// fedify's authenticated document loader signs the request with a
// local actor's key so they return 200. Mirrors the `actorLoader`
// in handlers/inbox.ts.
//
// Absent `signAs` (e.g. a fresh instance with no keyed accounts), the
// fetch goes out unauthenticated — the same reach as before.

import { getAuthenticatedDocumentLoader, importJwk } from "@fedify/fedify";
import { cachedDocumentLoader } from "../fedify/context.ts";

export interface FetchPayload {
  uri: string;
  signAs?: {
    keyId: string;
    privateJwk: Record<string, unknown>;
    publicJwk?: Record<string, unknown>;
  };
}

export interface FetchResult {
  document: unknown;
}

export async function handleFetch(payload: FetchPayload): Promise<FetchResult> {
  let loader: typeof cachedDocumentLoader = cachedDocumentLoader;

  if (payload.signAs) {
    const privateKey = await importJwk(
      payload.signAs.privateJwk as Parameters<typeof importJwk>[0],
      "private",
    );
    loader = getAuthenticatedDocumentLoader({
      keyId: new URL(payload.signAs.keyId),
      privateKey,
    }) as typeof cachedDocumentLoader;
  }

  const result = await loader(payload.uri);
  return { document: result.document };
}
