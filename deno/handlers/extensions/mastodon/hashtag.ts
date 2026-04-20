import { Create, Hashtag, Note } from "@fedify/fedify";
import { signAndSerialize } from "../../../fedify/utils.ts";

export interface HashtagItem {
  name: string;
  href: string;
}

export interface BuildNoteHashtagPayload {
  actor: string;
  content: string;
  hashtags: HashtagItem[];
  noteId: string;
  activityId: string;
  recipientInboxes: string[];
}

export interface BuildNoteHashtagResult {
  note: unknown;
  recipientInboxes: string[];
}

export async function handleBuildNoteHashtag(
  payload: BuildNoteHashtagPayload,
): Promise<BuildNoteHashtagResult> {
  const tags = payload.hashtags.map(
    (h) =>
      new Hashtag({
        name: h.name,
        href: new URL(h.href),
      }),
  );
  const note = new Note({
    id: new URL(payload.noteId),
    attribution: new URL(payload.actor),
    content: payload.content,
    tags,
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
