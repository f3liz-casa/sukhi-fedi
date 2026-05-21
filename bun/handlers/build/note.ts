import { Create, Note } from "@fedify/fedify";
import { Temporal } from "@js-temporal/polyfill";
import { injectMisskey, injectQuote, signAndSerialize } from "../../fedify/utils.ts";
import { resolveAudience } from "../../fedify/addressing.ts";

export interface BuildNotePayload {
  actor: string;
  content: string;
  recipientInboxes: string[];
  noteId: string;
  activityId: string;
  // AP id of a quoted note, when this note is a 引用ノート. Optional.
  quoteUrl?: string;
}

export interface BuildNoteResult {
  note: unknown;
  recipientInboxes: string[];
}

export async function handleBuildNote(
  payload: BuildNotePayload,
): Promise<BuildNoteResult> {
  const audience = resolveAudience({ kind: "public", actor: payload.actor });

  const note = new Note({
    id: new URL(payload.noteId),
    attribution: new URL(payload.actor),
    content: payload.content,
    published: Temporal.Now.instant(),
    tos: audience.tos,
    ccs: audience.ccs,
  });

  const create = new Create({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: note,
    tos: audience.tos,
    ccs: audience.ccs,
  });

  const noteJson = await signAndSerialize(payload.actor, create);
  injectMisskey(noteJson, payload.content);
  injectQuote(noteJson, payload.quoteUrl);

  return {
    note: noteJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
