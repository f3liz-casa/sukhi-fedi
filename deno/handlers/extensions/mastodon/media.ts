import { Create, Document, Note } from "@fedify/fedify";
import { signAndSerialize } from "../../fedify/utils.ts";

export interface MediaAttachment {
  url: string;
  mediaType: string;
  blurhash?: string;
  width?: number;
  height?: number;
  name?: string;
}

export interface BuildNoteMediaPayload {
  actor: string;
  content: string;
  attachments: MediaAttachment[];
  noteId: string;
  activityId: string;
  recipientInboxes: string[];
}

export interface BuildNoteMediaResult {
  note: unknown;
  recipientInboxes: string[];
}

export async function handleBuildNoteMedia(
  payload: BuildNoteMediaPayload,
): Promise<BuildNoteMediaResult> {
  const attachments = payload.attachments.map((a) =>
    new Document({
      url: new URL(a.url),
      mediaType: a.mediaType,
      name: a.name ?? null,
      width: a.width ?? null,
      height: a.height ?? null,
    })
  );
  const note = new Note({
    id: new URL(payload.noteId),
    attribution: new URL(payload.actor),
    content: payload.content,
    attachments,
    published: Temporal.Now.instant(),
  });
  const create = new Create({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: note,
  });
  const noteJson = await signAndSerialize(payload.actor, create) as Record<string, unknown>;
  // Inject blurhash into attachment objects (not natively supported by fedify)
  if (noteJson["object"] && typeof noteJson["object"] === "object") {
    const obj = noteJson["object"] as Record<string, unknown>;
    const attachArr = Array.isArray(obj["attachment"])
      ? (obj["attachment"] as Record<string, unknown>[])
      : obj["attachment"]
      ? [obj["attachment"] as Record<string, unknown>]
      : [];
    payload.attachments.forEach((a, i) => {
      if (a.blurhash && attachArr[i]) {
        attachArr[i]["blurhash"] = a.blurhash;
      }
    });
    if (attachArr.length > 0) {
      obj["attachment"] = attachArr;
    }
  }
  return {
    note: noteJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
