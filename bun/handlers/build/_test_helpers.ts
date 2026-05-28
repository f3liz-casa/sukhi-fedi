// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Test-side helpers for inspecting serialized AP JSON-LD.
// Fedify emits compact form (`as:Public`) which is semantically equal
// to the full URL — assertions must accept both.

import { exportJwk, generateCryptoKeyPair } from "@fedify/fedify";
import type { SignedPayload } from "../../fedify/utils.ts";
import type { JwkInput } from "../../fedify/key_cache.ts";
import { AS_PUBLIC_URL } from "../../fedify/addressing.ts";

// Lazy: generating an RSA-2048 keypair costs ~80 ms in WebCrypto, so
// share one pair across the whole test run.
let cachedCreds: SignedPayload | null = null;

export async function testCreds(
  actor: string = "https://watch.example/users/alice",
): Promise<SignedPayload> {
  if (cachedCreds == null) {
    const { privateKey } = await generateCryptoKeyPair("RSASSA-PKCS1-v1_5");
    const privateKeyJwk = (await exportJwk(privateKey)) as JwkInput;
    cachedCreds = { privateKeyJwk, keyId: `${actor}#main-key` };
  }
  return cachedCreds;
}

export function asStrings(field: unknown): string[] {
  if (Array.isArray(field)) return field.map(String);
  if (field == null) return [];
  return [String(field)];
}

const PUBLIC_FORMS = new Set<string>([
  AS_PUBLIC_URL.href,
  "as:Public",
  "Public",
  "https://www.w3.org/ns/activitystreams#Public",
]);

export function containsPublic(field: unknown): boolean {
  return asStrings(field).some((v) => PUBLIC_FORMS.has(v));
}

export function containsFollowers(field: unknown, actor: string): boolean {
  const needle = `${actor}/followers`;
  return asStrings(field).includes(needle);
}
