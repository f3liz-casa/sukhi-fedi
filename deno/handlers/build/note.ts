import { Create, Note, fetchDocumentLoader, signObject } from "@fedify/fedify";
import { getOrCreateKey } from "../../fedify/keys.ts";

export interface BuildNotePayload {
  actor: string;
  content: string;
  recipientInboxes: string[];
  noteId: string;
  activityId: string;
}

export interface BuildNoteResult {
  note: unknown;
  recipientInboxes: string[];
}

export async function handleBuildNote(
  payload: BuildNotePayload,
): Promise<BuildNoteResult> {
  const documentLoader = fetchDocumentLoader;
  const { privateKey, keyId } = await getOrCreateKey(payload.actor);

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

  const signed = await signObject(create, privateKey, new URL(keyId), {
    documentLoader,
  });

  const noteJson = await signed.toJsonLd({ contextLoader: documentLoader });

  return {
    note: noteJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
