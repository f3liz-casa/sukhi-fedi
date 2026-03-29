import { connect } from "nats";
import { tracer, SpanStatusCode } from "./otel.ts";
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
import { handleWebFinger } from "./handlers/wellknown/webfinger.ts";
import { handleNodeInfo } from "./handlers/wellknown/nodeinfo.ts";
import { handleSignDelivery } from "./handlers/sign_delivery.ts";
import { handleBuildDm } from "./handlers/build/dm.ts";
import { handleBuildAdd, handleBuildRemove } from "./handlers/build/collection_op.ts";
import { handleBuildIntegrityProof } from "./handlers/build/integrity_proof.ts";
import { createApi } from "./api.ts";

const nc = await connect({ servers: Deno.env.get("NATS_URL") ?? "nats://localhost:4222" });

async function subscribe<T>(subject: string, handler: (payload: T) => Promise<unknown>) {
  const sub = nc.subscribe(subject);
  for await (const msg of sub) {
    const envelope = JSON.parse(new TextDecoder().decode(msg.data)) as {
      request_id: string;
      payload: T;
    };
    await tracer.startActiveSpan(`nats ${subject}`, async (span) => {
      span.setAttributes({
        "messaging.system": "nats",
        "messaging.destination": subject,
        "messaging.message_id": envelope.request_id,
      });
      try {
        const data = await handler(envelope.payload);
        msg.respond(new TextEncoder().encode(JSON.stringify({ ok: true, data })));
        span.setStatus({ code: SpanStatusCode.OK });
      } catch (err) {
        const error = err instanceof Error ? err.message : String(err);
        span.setStatus({ code: SpanStatusCode.ERROR, message: error });
        span.recordException(err instanceof Error ? err : new Error(error));
        msg.respond(new TextEncoder().encode(JSON.stringify({ ok: false, error })));
      } finally {
        span.end();
      }
    });
  }
}

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
  subscribe("ap.webfinger", handleWebFinger),
  subscribe("ap.nodeinfo", () => handleNodeInfo()),
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

// ── HTTP server (proxied from Elixir via ProxyPlug) ───────────────────────────
const port = parseInt(Deno.env.get("PORT") ?? "8000");
const api = createApi(nc);
Deno.serve({ port }, api.fetch);

console.log(`Deno worker started — HTTP on :${port}, NATS connected`);
