// SPDX-License-Identifier: MPL-2.0
import { signRequest, importJwk } from "@fedify/fedify";

export interface SignDeliveryPayload {
  actorUri: string;
  inbox: string;
  body: string;
  privateKeyJwk: JsonWebKey;
  keyId: string;
  /**
   * Preferred HTTP Signature algorithm.
   * - "rfc9421"  → Signature-Input + Signature headers (RFC 9421)
   * - "cavage"   → single Signature header (draft-cavage, default)
   *
   * Fedify's verifyRequest accepts both on the receiving side, so either
   * format is interoperable. Choosing "rfc9421" makes outbound deliveries
   * compliant with the modern standard.
   */
  algorithm?: "rfc9421" | "cavage";
}

export interface SignDeliveryResult {
  headers: Record<string, string>;
}

export async function handleSignDelivery(
  payload: SignDeliveryPayload,
): Promise<SignDeliveryResult> {
  const privateKey = await importJwk(payload.privateKeyJwk, "private");

  const request = new Request(payload.inbox, {
    method: "POST",
    headers: {
      "Content-Type": "application/activity+json",
      "User-Agent": "sukhi-fedi/0.1.0",
    },
    body: payload.body,
  });

  // Fedify 1.x signRequest options — attempt RFC 9421 when requested.
  // The `preferRfc9421` option was added in Fedify 1.3.0 (available in 1.10.4).
  const signOptions: Record<string, unknown> = {};
  if (payload.algorithm === "rfc9421") {
    signOptions.preferRfc9421 = true;
  }

  let signed: Request;
  try {
    signed = await signRequest(request, privateKey, new URL(payload.keyId), signOptions as Parameters<typeof signRequest>[3]);
  } catch {
    // Fallback: sign without extra options (cavage format)
    signed = await signRequest(request, privateKey, new URL(payload.keyId));
  }

  const outHeaders: Record<string, string> = {};
  signed.headers.forEach((v, k) => {
    outHeaders[k] = v;
  });
  return { headers: outHeaders };
}
