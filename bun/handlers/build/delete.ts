import { Delete, Tombstone } from "@fedify/fedify";
import { Temporal } from "@js-temporal/polyfill";
import { signAndSerialize } from "../../fedify/utils.ts";
import { resolveAudience } from "../../fedify/addressing.ts";

export interface BuildDeletePayload {
  actor: string;
  activityId: string;
  // The AP id of the object being deleted (Note, Article, …).
  objectId: string;
  recipientInboxes: string[];
}

export interface BuildDeleteResult {
  delete: unknown;
  recipientInboxes: string[];
}

export async function handleBuildDelete(
  payload: BuildDeletePayload,
): Promise<BuildDeleteResult> {
  const audience = resolveAudience({ kind: "public", actor: payload.actor });

  const tombstone = new Tombstone({ id: new URL(payload.objectId) });

  const del = new Delete({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: tombstone,
    published: Temporal.Now.instant(),
    tos: audience.tos,
    ccs: audience.ccs,
  });

  const deleteJson = await signAndSerialize(payload.actor, del);

  return {
    delete: deleteJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
