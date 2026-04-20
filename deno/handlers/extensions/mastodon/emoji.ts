import { Create, Emoji, Image, Note } from "@fedify/fedify";
import { signAndSerialize } from "../../../fedify/utils.ts";

export interface CustomEmojiItem {
  name: string;
  iconUrl: string;
}

export interface BuildNoteEmojiPayload {
  actor: string;
  content: string;
  emojis: CustomEmojiItem[];
  noteId: string;
  activityId: string;
  recipientInboxes: string[];
}

export interface BuildNoteEmojiResult {
  note: unknown;
  recipientInboxes: string[];
}

export async function handleBuildNoteEmoji(
  payload: BuildNoteEmojiPayload,
): Promise<BuildNoteEmojiResult> {
  const tags = payload.emojis.map(
    (e) =>
      new Emoji({
        id: new URL(`${payload.actor}#emoji-${e.name}`),
        name: e.name,
        icon: new Image({
          url: new URL(e.iconUrl),
          mediaType: "image/png",
        }),
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
