// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Test-side helpers for inspecting serialized AP JSON-LD.
// Fedify emits compact form (`as:Public`) which is semantically equal
// to the full URL — assertions must accept both.

import { AS_PUBLIC_URL } from "../../fedify/addressing.ts";

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
