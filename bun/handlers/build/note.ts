import { Create, Note, signObject } from "@fedify/fedify";
import { Temporal } from "@js-temporal/polyfill";
import { cachedDocumentLoader as fetchDocumentLoader } from "../../fedify/context.ts";
import { getOrCreateKey } from "../../fedify/keys.ts";
import { injectDefined } from "../../fedify/utils.ts";

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

  // Public addressing. Without `tos: [Public]` receivers like iceshrimp
  // can't classify visibility and silently drop the note from timelines
  // even though it sits in their inbox. `ccs: [followers]` is the
  // Mastodon-compatible shape for a public, follower-visible post.
  const publicNs = new URL("https://www.w3.org/ns/activitystreams#Public");
  const followers = new URL(`${payload.actor}/followers`);

  const note = new Note({
    id: new URL(payload.noteId),
    attribution: new URL(payload.actor),
    content: payload.content,
    published: Temporal.Now.instant(),
    tos: [publicNs],
    ccs: [followers],
  });

  const create = new Create({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: note,
    tos: [publicNs],
    ccs: [followers],
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
