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
}

export async function handleVerify(payload: VerifyPayload): Promise<VerifyResult> {
  const request = new Request(payload.url, {
    method: payload.method,
    headers: payload.headers,
    body: payload.raw,
  });
  const documentLoader = fetchDocumentLoader;
  const result = await verifyRequest(request, { documentLoader });
  return { ok: result != null };
}
