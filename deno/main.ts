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
import { handleWebFinger } from "./handlers/wellknown/webfinger.ts";
import { handleNodeInfo } from "./handlers/wellknown/nodeinfo.ts";
import { createApi } from "./api.ts";

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
      msg.respond(new TextEncoder().encode(JSON.stringify({ ok: false, error })));
    }
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
  subscribe("ap.webfinger", handleWebFinger),
  subscribe("ap.nodeinfo", () => handleNodeInfo()),
  ...registerMisskeyHandlers(subscribe),
  ...registerMastodonHandlers(subscribe),
]);

// ── HTTP server (proxied from Elixir via ProxyPlug) ───────────────────────────
const port = parseInt(Deno.env.get("PORT") ?? "8000");
const api = createApi(nc);
Deno.serve({ port }, api.fetch);

console.log(`Deno worker started — HTTP on :${port}, NATS connected`);
