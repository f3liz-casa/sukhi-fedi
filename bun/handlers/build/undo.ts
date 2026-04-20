import { Like, Follow, Undo, signObject } from "@fedify/fedify";
import { Temporal } from "@js-temporal/polyfill";
import { cachedDocumentLoader as fetchDocumentLoader } from "../../fedify/context.ts";
import { getOrCreateKey } from "../../fedify/keys.ts";

export interface BuildUndoPayload {
  actor: string;
  activityId: string;
  recipientInboxes: string[];
  // The activity being undone. Must be one we own (we re-construct a
  // minimal stub so the receiver can match it by `id`).
  inner: {
    type: "Like" | "Follow";
    id: string;
    object: string;
  };
}

export interface BuildUndoResult {
  undo: unknown;
  recipientInboxes: string[];
}

export async function handleBuildUndo(
  payload: BuildUndoPayload,
): Promise<BuildUndoResult> {
  const documentLoader = fetchDocumentLoader;
  const { privateKey, keyId } = await getOrCreateKey(payload.actor);

  const inner = payload.inner.type === "Like"
    ? new Like({
        id: new URL(payload.inner.id),
        actor: new URL(payload.actor),
        object: new URL(payload.inner.object),
      })
    : new Follow({
        id: new URL(payload.inner.id),
        actor: new URL(payload.actor),
        object: new URL(payload.inner.object),
      });

  const undo = new Undo({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: inner,
    published: Temporal.Now.instant(),
  });

  const signed = await signObject(undo, privateKey, new URL(keyId), {
    documentLoader,
  });

  const undoJson = await signed.toJsonLd({ contextLoader: documentLoader });

  return {
    undo: undoJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
