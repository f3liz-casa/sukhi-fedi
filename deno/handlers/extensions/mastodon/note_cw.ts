import { Create, Note } from "@fedify/fedify";
import { signAndSerialize } from "../../../fedify/utils.ts";

export interface BuildNoteCwPayload {
  actor: string;
  content: string;
  summary: string;
  sensitive: boolean;
  noteId: string;
  activityId: string;
  recipientInboxes: string[];
}

export interface BuildNoteCwResult {
  note: unknown;
  recipientInboxes: string[];
}

export async function handleBuildNoteCw(
  payload: BuildNoteCwPayload,
): Promise<BuildNoteCwResult> {
  const note = new Note({
    id: new URL(payload.noteId),
    attribution: new URL(payload.actor),
    content: payload.content,
    summary: payload.summary,
    sensitive: payload.sensitive,
    published: Temporal.Now.instant(),
  });
  const create = new Create({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: note,
  });
  return {
    note: await signAndSerialize(payload.actor, create),
    recipientInboxes: payload.recipientInboxes,
  };
}
