import { Delete, Tombstone, signObject } from "@fedify/fedify";
import { Temporal } from "@js-temporal/polyfill";
import { cachedDocumentLoader as fetchDocumentLoader } from "../../fedify/context.ts";
import { getOrCreateKey } from "../../fedify/keys.ts";

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
  const documentLoader = fetchDocumentLoader;
  const { privateKey, keyId } = await getOrCreateKey(payload.actor);

  // Public addressing. Same reasoning as Create(Note): without `tos:
  // [Public]` and `ccs: [followers]` receivers that gate activity
  // application on visibility classification drop the Delete silently
  // and leave a ghost Note on their timelines.
  const publicNs = new URL("https://www.w3.org/ns/activitystreams#Public");
  const followers = new URL(`${payload.actor}/followers`);

  const tombstone = new Tombstone({ id: new URL(payload.objectId) });

  const del = new Delete({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: tombstone,
    published: Temporal.Now.instant(),
    tos: [publicNs],
    ccs: [followers],
  });

  const signed = await signObject(del, privateKey, new URL(keyId), {
    documentLoader,
  });

  const deleteJson = await signed.toJsonLd({ contextLoader: documentLoader });

  return {
    delete: deleteJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
