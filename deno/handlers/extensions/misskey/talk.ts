import { Create, Note } from "@fedify/fedify";
import { signAndSerialize } from "../../../fedify/utils.ts";

export interface BuildTalkPayload {
  actor: string;
  content: string;
  noteId: string;
  activityId: string;
  recipientInboxes: string[];
}

export interface BuildTalkResult {
  note: unknown;
  recipientInboxes: string[];
}

export async function handleBuildTalk(
  payload: BuildTalkPayload,
): Promise<BuildTalkResult> {
  const note = new Note({
    id: new URL(payload.noteId),
    attribution: new URL(payload.actor),
    content: payload.content,
    published: Temporal.Now.instant(),
  });
  const create = new Create({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: note,
  });
  const noteJson = await signAndSerialize(payload.actor, create) as Record<string, unknown>;
  // Inject _misskey_talk flag to distinguish chat messages from regular notes
  if (noteJson["object"] && typeof noteJson["object"] === "object") {
    (noteJson["object"] as Record<string, unknown>)["_misskey_talk"] = true;
  }
  return {
    note: noteJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
