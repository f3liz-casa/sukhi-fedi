// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Bun legacy `ap.*` worker.
//
// Only two subjects remain after the phase-out: `ap.verify` and
// `ap.inbox`. Everything else graduated to `services/fedify_service.ts`
// (NATS Micro, subjects `fedify.*`).
//
// Addon manifests in `addons/<id>/manifest.ts` can contribute extra
// `ap.*` subscribes; they are filtered against `ENABLED_ADDONS`.

import { connect } from "nats";
import { handleVerify } from "./handlers/verify.ts";
import { handleInbox } from "./handlers/inbox.ts";
import { enabledAddons } from "./addons/loader.ts";

const nc = await connect({ servers: process.env.NATS_URL ?? "nats://localhost:4222" });

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

const addons = enabledAddons();
console.log(
  `Bun ap.* worker started. Addons: ${
    addons.map((a) => a.id).join(",") || "(none)"
  }`,
);

const coreSubs: Promise<void>[] = [
  subscribe("ap.verify", handleVerify),
  subscribe("ap.inbox", handleInbox),
];

const addonSubs = addons.flatMap((a) => (a.subscribes ? a.subscribes(subscribe) : []));

await Promise.all([...coreSubs, ...addonSubs]);
