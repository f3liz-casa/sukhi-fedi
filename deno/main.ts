// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Legacy NATS worker. Listens on the `ap.*` subject prefixes for
// operations not yet migrated to `services/fedify_service.ts` (NATS
// Micro). Deletion of these subscribes is scheduled once every Elixir
// caller has been switched over to FedifyClient.
//
// This process no longer runs an HTTP server — WebFinger and NodeInfo
// are served directly by Elixir, and the Mastodon/Misskey API is the
// responsibility of the Elixir gateway (stage 3-b ongoing).
import { connect } from "nats";
import { handleAuth } from "./handlers/auth.ts";
import { handleVerify } from "./handlers/verify.ts";
import { handleInbox } from "./handlers/inbox.ts";
import { handleBuildNote } from "./handlers/build/note.ts";
import { handleBuildFollow } from "./handlers/build/follow.ts";
import { handleBuildAccept } from "./handlers/build/accept.ts";
import { handleBuildAnnounce } from "./handlers/build/announce.ts";
import { handleBuildActor } from "./handlers/build/actor.ts";
import { handleCreateAccount } from "./handlers/account.ts";
import { handleCreateToken } from "./handlers/token.ts";
import { registerMisskeyHandlers } from "./handlers/extensions/misskey.ts";
import { registerMastodonHandlers } from "./handlers/extensions/mastodon.ts";
import { handleSignDelivery } from "./handlers/sign_delivery.ts";
import { handleBuildDm } from "./handlers/build/dm.ts";
import { handleBuildAdd, handleBuildRemove } from "./handlers/build/collection_op.ts";
import { handleBuildIntegrityProof } from "./handlers/build/integrity_proof.ts";

const nc = await connect({ servers: Deno.env.get("NATS_URL") ?? "nats://localhost:4222" });

async function subscribe<T>(subject: string, handler: (payload: T) => Promise<unknown>) {
  const sub = nc.subscribe(subject);
  for await (const msg of sub) {
    const envelope = JSON.parse(new TextDecoder().decode(msg.data)) as {
      request_id: string;
      payload: T;
    };
    try {
      const data = await handler(envelope.payload);
      msg.respond(new TextEncoder().encode(JSON.stringify({ ok: true, data })));
    } catch (err) {
      const error = err instanceof Error ? err.message : String(err);
      console.error(`[${subject}] ${envelope.request_id} error: ${error}`);
      msg.respond(new TextEncoder().encode(JSON.stringify({ ok: false, error })));
    }
  }
}

console.log("Deno legacy ap.* worker started (no HTTP server).");

// ── NATS workers (ap.* subjects) ─────────────────────────────────────────────
await Promise.all([
  subscribe("ap.auth", handleAuth),
  subscribe("ap.verify", handleVerify),
  subscribe("ap.inbox", handleInbox),
  subscribe("ap.build.note", handleBuildNote),
  subscribe("ap.build.follow", handleBuildFollow),
  subscribe("ap.build.accept", handleBuildAccept),
  subscribe("ap.build.announce", handleBuildAnnounce),
  subscribe("ap.build.actor", handleBuildActor),
  subscribe("ap.account.create", handleCreateAccount),
  subscribe("ap.token.create", handleCreateToken),
  subscribe("ap.sign_delivery", handleSignDelivery),
  // DMs / Conversations
  subscribe("ap.build.dm", handleBuildDm as (payload: unknown) => Promise<unknown>),
  // Featured collection (pinned posts) — FEP-e232
  subscribe("ap.build.add", handleBuildAdd as (payload: unknown) => Promise<unknown>),
  subscribe("ap.build.remove", handleBuildRemove as (payload: unknown) => Promise<unknown>),
  // FEP-8b32: Object Integrity Proofs
  subscribe("ap.build.integrity_proof", handleBuildIntegrityProof as (payload: unknown) => Promise<unknown>),
  ...registerMisskeyHandlers(subscribe),
  ...registerMastodonHandlers(subscribe),
]);
