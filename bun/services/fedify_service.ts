// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Fedify NATS Micro service.
//
// Exposes four endpoints to Elixir via NATS request/reply:
//   - fedify.ping.v1      : health check / liveness probe
//   - fedify.translate.v1 : build ActivityPub JSON-LD from a domain object
//   - fedify.sign.v1      : HTTP-Signature an outbound request envelope
//   - fedify.verify.v1    : verify an incoming signed HTTP request
//
// Multiple replicas can run in parallel. NATS Micro queue-groups them
// automatically via `queue: "fedify-workers"` so load is balanced across
// instances.
//
// Running: NATS_URL=nats://localhost:4222 bun run services/fedify_service.ts
// Testing: nats --server nats://localhost:4222 req fedify.ping.v1 hello

import { connect, type NatsConnection } from "nats";
import { Svcm, type Service } from "@nats-io/services";

import { handleBuildNote } from "../handlers/build/note.ts";
import { handleBuildFollow } from "../handlers/build/follow.ts";
import { handleBuildAccept } from "../handlers/build/accept.ts";
import { handleBuildAnnounce } from "../handlers/build/announce.ts";
import { handleBuildActor } from "../handlers/build/actor.ts";
import { handleBuildDm } from "../handlers/build/dm.ts";
import { handleBuildAdd, handleBuildRemove } from "../handlers/build/collection_op.ts";
import { handleSignDelivery } from "../handlers/sign_delivery.ts";
import { handleVerify } from "../handlers/verify.ts";
import { mergedTranslators } from "../addons/loader.ts";
import type { TranslateHandler } from "../addons/types.ts";

// deno-lint-ignore no-explicit-any
type AnyMsg = any;

const dec = new TextDecoder();
const enc = new TextEncoder();

// Core `translate.v1` dispatch table — ActivityPub-ish domain object
// types built into every deployment. Addons contribute additional
// namespaced keys (`<addon_id>.<type>`) via their manifest.
const CORE_TRANSLATORS: Record<string, TranslateHandler> = {
  note: handleBuildNote as TranslateHandler,
  follow: handleBuildFollow as TranslateHandler,
  accept: handleBuildAccept as TranslateHandler,
  announce: handleBuildAnnounce as TranslateHandler,
  actor: handleBuildActor as TranslateHandler,
  dm: handleBuildDm as TranslateHandler,
  add: handleBuildAdd as TranslateHandler,
  remove: handleBuildRemove as TranslateHandler,
};

const TRANSLATORS: Record<string, TranslateHandler> = mergedTranslators(CORE_TRANSLATORS);

function respondOk(msg: AnyMsg, data: unknown) {
  msg.respond(enc.encode(JSON.stringify({ ok: true, data })));
}

function respondError(msg: AnyMsg, error: string) {
  msg.respond(enc.encode(JSON.stringify({ ok: false, error })));
}

async function handleTranslate(msg: AnyMsg) {
  try {
    const body = JSON.parse(dec.decode(msg.data)) as {
      object_type: string;
      payload: unknown;
    };
    const handler = TRANSLATORS[body.object_type];
    if (!handler) {
      respondError(msg, `unknown object_type: ${body.object_type}`);
      return;
    }
    const result = await handler(body.payload);
    respondOk(msg, result);
  } catch (e) {
    respondError(msg, e instanceof Error ? e.message : String(e));
  }
}

async function handleSign(msg: AnyMsg) {
  try {
    const body = JSON.parse(dec.decode(msg.data));
    const result = await handleSignDelivery(body);
    respondOk(msg, result);
  } catch (e) {
    respondError(msg, e instanceof Error ? e.message : String(e));
  }
}

async function handleVerifyMicro(msg: AnyMsg) {
  try {
    const body = JSON.parse(dec.decode(msg.data));
    const result = await handleVerify(body);
    respondOk(msg, result);
  } catch (e) {
    respondError(msg, e instanceof Error ? e.message : String(e));
  }
}

export interface StartedService {
  service: Service;
  nc: NatsConnection;
  stop: () => Promise<void>;
}

export async function startFedifyService(
  natsUrl: string = "nats://localhost:4222",
): Promise<StartedService> {
  const nc = await connect({ servers: natsUrl });

  const svcm = new Svcm(nc);
  const service = await svcm.add({
    name: "fedify",
    version: "0.2.0",
    description: "sukhi-fedi Fedify translator / signer / verifier",
    queue: "fedify-workers",
  });

  const grp = service.addGroup("fedify");

  grp.addEndpoint("ping.v1", (err, msg) => {
    if (err) {
      service.stop(err as Error);
      return;
    }
    msg.respond(msg.data);
  });

  grp.addEndpoint("translate.v1", (err, msg) => {
    if (err) return service.stop(err as Error);
    void handleTranslate(msg);
  });

  grp.addEndpoint("sign.v1", (err, msg) => {
    if (err) return service.stop(err as Error);
    void handleSign(msg);
  });

  grp.addEndpoint("verify.v1", (err, msg) => {
    if (err) return service.stop(err as Error);
    void handleVerifyMicro(msg);
  });

  const stop = async () => {
    await service.stop();
    await nc.drain();
  };

  return { service, nc, stop };
}

if (import.meta.main) {
  const url = process.env.NATS_URL ?? "nats://localhost:4222";
  const { service, stop } = await startFedifyService(url);

  const shutdown = async () => {
    console.log("shutting down fedify service...");
    await stop();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  const info = service.info();
  console.log("fedify service started");
  console.log(`  name:      ${info.name}`);
  console.log(`  version:   ${info.version}`);
  console.log(`  id:        ${info.id}`);
  console.log(`  queue:     fedify-workers`);
  console.log(`  endpoints: fedify.{ping,translate,sign,verify}.v1`);
  console.log(`  NATS URL:  ${url}`);

  // Block forever; signal handler takes care of shutdown.
  await new Promise(() => {});
}
