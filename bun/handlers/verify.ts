import { verifyRequest } from "@fedify/fedify";
import { cachedDocumentLoader as fetchDocumentLoader } from "../fedify/context.ts";

export interface VerifyPayload {
  raw: string;
  headers: Record<string, string>;
  method: string;
  url: string;
}

export interface VerifyResult {
  ok: boolean;
  // On a good signature, identify *who* signed: the signing key's id
  // (keyId) and its owner (the actor the key belongs to). Elixir binds
  // this to the activity's claimed `actor` so a server cannot sign
  // activities on behalf of another server's actor. `verifyRequest` only
  // proves "the holder of keyId's private key signed these bytes" — it
  // does not, on its own, check that holder is the activity's actor.
  keyId?: string | null;
  owner?: string | null;
}

export async function handleVerify(payload: VerifyPayload): Promise<VerifyResult> {
  const request = new Request(payload.url, {
    method: payload.method,
    headers: payload.headers,
    body: payload.raw,
  });
  const documentLoader = fetchDocumentLoader;
  const key = await verifyRequest(request, { documentLoader });
  // A null result means no/invalid signature. Return ok:false so the
  // Elixir side rejects it — previously the boolean was discarded and an
  // unsigned activity was executed anyway.
  if (key == null) return { ok: false };
  return {
    ok: true,
    keyId: key.id?.href ?? null,
    owner: key.ownerId?.href ?? null,
  };
}
