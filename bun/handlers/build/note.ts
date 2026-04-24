import { Create, Note, signObject } from "@fedify/fedify";
import { Temporal } from "@js-temporal/polyfill";
import { cachedDocumentLoader as fetchDocumentLoader } from "../../fedify/context.ts";
import { getOrCreateKey } from "../../fedify/keys.ts";
import { injectDefined } from "../../fedify/utils.ts";
import { resolveAudience } from "../../fedify/addressing.ts";

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

  const signed = await signObject(create, privateKey, new URL(keyId), {
    documentLoader,
  });

  const noteJson = await signed.toJsonLd({ contextLoader: documentLoader }) as Record<string, unknown>;
  // Inject _misskey_content so Misskey can render the plain-text/MFM content
  if (noteJson["object"] && typeof noteJson["object"] === "object") {
    injectDefined(noteJson["object"] as Record<string, unknown>, {
      _misskey_content: payload.content,
    });
  }

  return {
    note: noteJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
