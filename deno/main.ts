import { connect } from "nats";
import { handleAuth } from "./handlers/auth.ts";
import { handleVerify } from "./handlers/verify.ts";
import { handleInbox } from "./handlers/inbox.ts";
import { handleBuildNote } from "./handlers/build/note.ts";
import { handleBuildFollow } from "./handlers/build/follow.ts";
import { handleBuildAccept } from "./handlers/build/accept.ts";
import { handleWebFinger } from "./handlers/wellknown/webfinger.ts";
import { handleNodeInfo } from "./handlers/wellknown/nodeinfo.ts";

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

await Promise.all([
  subscribe("ap.auth", handleAuth),
  subscribe("ap.verify", handleVerify),
  subscribe("ap.inbox", handleInbox),
  subscribe("ap.build.note", handleBuildNote),
  subscribe("ap.build.follow", handleBuildFollow),
  subscribe("ap.build.accept", handleBuildAccept),
  subscribe("ap.webfinger", handleWebFinger),
  subscribe("ap.nodeinfo", () => handleNodeInfo()),
]);

console.log("Deno NATS worker started");
