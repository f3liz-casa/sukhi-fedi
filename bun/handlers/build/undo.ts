import { EmojiReact, Like, Follow, Undo } from "@fedify/fedify/vocab";
import { nowInstant } from "../../fedify/temporal.ts";
import { signAndSerialize } from "../../fedify/utils.ts";
import { mirrorAudience } from "../../fedify/addressing.ts";

export interface BuildUndoPayload {
  actor: string;
  activityId: string;
  recipientInboxes: string[];
  // The activity being undone. Must be one we own (we re-construct a
  // minimal stub so the receiver can match it by `id`).
  inner: {
    type: "Like" | "EmojiReact" | "Follow";
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
  const innerArgs = {
    id: new URL(payload.inner.id),
    actor: new URL(payload.actor),
    object: new URL(payload.inner.object),
  };

  const inner = payload.inner.type === "Like"
    ? new Like(innerArgs)
    : payload.inner.type === "EmojiReact"
    ? new EmojiReact(innerArgs)
    : new Follow(innerArgs);

  const audience = mirrorAudience(payload.inner.object);

  const undo = new Undo({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: inner,
    published: nowInstant(),
    tos: audience.tos,
    ccs: audience.ccs,
  });

  const undoJson = await signAndSerialize(payload.actor, undo);

  return {
    undo: undoJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
