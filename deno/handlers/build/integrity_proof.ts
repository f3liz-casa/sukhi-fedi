// SPDX-License-Identifier: AGPL-3.0-or-later
//
// FEP-8b32: Object Integrity Proofs
//
// Attaches an eddsa-jcs-2022 DataIntegrityProof to an already-serialised
// AP object. The proof is generated using Ed25519 over the JCS-canonicalised
// object, giving recipients a way to verify the object without relying on
// HTTP-level transport security.
//
// Fedify exposes `createProof` for this purpose. If the runtime version of
// Fedify does not export `createProof`, the proof is computed manually using
// the Web Crypto API and JCS canonicalisation.

import { getOrCreateKey } from "../../fedify/keys.ts";

export interface IntegrityProofPayload {
  /** Local actor URI whose key will sign the proof. */
  actorUri: string;
  /** Already-serialised AP object JSON. */
  object: Record<string, unknown>;
}

export type IntegrityProofResult = Record<string, unknown>;

/**
 * Attach a FEP-8b32 DataIntegrityProof to `payload.object` and return the
 * augmented object.
 */
export async function handleBuildIntegrityProof(
  payload: IntegrityProofPayload,
): Promise<IntegrityProofResult> {
  const { privateKey, keyId } = await getOrCreateKey(payload.actorUri);

  // Try Fedify's createProof first (available in Fedify ≥1.3).
  // We import dynamically to avoid a hard failure if the export is missing.
  try {
    const { createProof } = await import("@fedify/fedify");
    if (typeof createProof === "function") {
      // createProof works on Fedify Activity objects, not raw JSON, so we
      // manually build the proof using the low-level approach below instead.
    }
  } catch {
    // Fall through to manual implementation
  }

  // Manual eddsa-jcs-2022 implementation:
  // 1. JCS-canonicalise the object (deterministic JSON stringify)
  // 2. Sign with Ed25519
  // 3. Encode signature as base58btc multibase
  const proofOptions: Record<string, unknown> = {
    type: "DataIntegrityProof",
    cryptosuite: "eddsa-jcs-2022",
    verificationMethod: keyId,
    proofPurpose: "assertionMethod",
    created: new Date().toISOString(),
  };

  // JCS: deterministic JSON (sorted keys, no extra whitespace)
  const canonicalObject = canonicalize(payload.object);
  const canonicalProofConfig = canonicalize(proofOptions);

  const encoder = new TextEncoder();
  const toSign = concat(
    encoder.encode(canonicalProofConfig),
    encoder.encode(canonicalObject),
  );

  const signature = await crypto.subtle.sign(
    { name: "Ed25519" },
    privateKey,
    toSign,
  );

  const proofValue = encodeBase58btc(new Uint8Array(signature));

  return {
    ...payload.object,
    proof: {
      ...proofOptions,
      proofValue,
    },
  };
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/** JSON Canonicalization Scheme (RFC 8785) — sort keys recursively. */
function canonicalize(value: unknown): string {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return "[" + value.map(canonicalize).join(",") + "]";
  }
  const keys = Object.keys(value as Record<string, unknown>).sort();
  const pairs = keys.map(
    (k) => JSON.stringify(k) + ":" + canonicalize((value as Record<string, unknown>)[k]),
  );
  return "{" + pairs.join(",") + "}";
}

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const result = new Uint8Array(a.length + b.length);
  result.set(a, 0);
  result.set(b, a.length);
  return result;
}

/** Encode bytes as base58btc (multibase prefix 'z'). */
function encodeBase58btc(bytes: Uint8Array): string {
  const ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
  let num = BigInt("0x" + Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join(""));
  let result = "";
  while (num > 0n) {
    result = ALPHABET[Number(num % 58n)] + result;
    num = num / 58n;
  }
  // Leading zeros
  for (const byte of bytes) {
    if (byte !== 0) break;
    result = "1" + result;
  }
  return "z" + result; // multibase prefix for base58btc
}
