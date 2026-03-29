// SPDX-License-Identifier: AGPL-3.0-or-later
import type { NatsConnection } from "nats";

export async function handleBlock(nc: NatsConnection, data: any) {
  const { actor, object } = data;
  
  // Store block in database via NATS
  await nc.publish("ap.block.store", JSON.stringify({
    actor_uri: actor,
    target_uri: object
  }));
  
  return { status: "ok" };
}

export async function handleFlag(nc: NatsConnection, data: any) {
  const { actor, object, content } = data;
  
  // Store report in database via NATS
  await nc.publish("ap.flag.store", JSON.stringify({
    actor_uri: actor,
    target_uri: Array.isArray(object) ? object[0] : object,
    comment: content || ""
  }));
  
  return { status: "ok" };
}
