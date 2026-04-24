// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Single source of truth for ActivityPub audience (to/cc).
//
// History: Create(Note) (887afb9f) and Delete(Note) (be3aa82) shipped
// without to/cc because each builder minted the URLs by hand. Receivers
// that gate visibility on addressing (iceshrimp, Mastodon) silently
// dropped the activity. Keep addressing in one place so the next
// builder can't re-introduce the same bug.

export const AS_PUBLIC_URL = new URL("https://www.w3.org/ns/activitystreams#Public");

export function followersUrlFor(actor: string): URL {
  return new URL(`${actor}/followers`);
}

export type Audience =
  | { kind: "public"; actor: string }
  | { kind: "followers_only"; actor: string }
  | { kind: "unlisted"; actor: string }
  | { kind: "direct"; actors: string[] };

export interface ResolvedAudience {
  tos: URL[];
  ccs: URL[];
}

export function resolveAudience(a: Audience): ResolvedAudience {
  switch (a.kind) {
    case "public":
      return { tos: [AS_PUBLIC_URL], ccs: [followersUrlFor(a.actor)] };
    case "unlisted":
      return { tos: [followersUrlFor(a.actor)], ccs: [AS_PUBLIC_URL] };
    case "followers_only":
      return { tos: [followersUrlFor(a.actor)], ccs: [] };
    case "direct":
      return { tos: a.actors.map((u) => new URL(u)), ccs: [] };
  }
}

// For Undo / Accept / Reject — audience should mirror what's being
// acted on. We don't have the full inner object here, only its AP id,
// so we address to that id. That's enough for the receiver to route
// the activity; the delivery set is driven separately by
// recipientInboxes.
export function mirrorAudience(innerObjectId: string): ResolvedAudience {
  return { tos: [new URL(innerObjectId)], ccs: [] };
}
