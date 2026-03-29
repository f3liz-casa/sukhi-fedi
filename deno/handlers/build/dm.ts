// SPDX-License-Identifier: MPL-2.0
import { Create, Note } from "@fedify/fedify";
import { signAndSerialize, injectDefined } from "../../fedify/utils.ts";

export interface BuildDmPayload {
  /** Local actor URI of the sender. */
  actor: string;
  /** HTML content of the message. */
  content: string;
  /** AP URIs of direct recipients (no AS#Public). */
  recipientActors: string[];
  /** AP ID for the Note object. */
  noteId: string;
  /** AP ID for the wrapping Create activity. */
  activityId: string;
  /** Remote inbox URLs to deliver to. */
  recipientInboxes: string[];
  /** Optional AP ID of the note this replies to. */
  inReplyToId?: string;
  /** Optional conversation context URI. */
  conversationId?: string;
}

export interface BuildDmResult {
  note: unknown;
  recipientInboxes: string[];
}

export async function handleBuildDm(payload: BuildDmPayload): Promise<BuildDmResult> {
  const note = new Note({
    id: new URL(payload.noteId),
    attribution: new URL(payload.actor),
    content: payload.content,
    published: Temporal.Now.instant(),
    tos: payload.recipientActors.map((u) => new URL(u)),
    // No `ccs` — direct message means explicitly addressed, not broadcast
    ...(payload.inReplyToId ? { replyTarget: new URL(payload.inReplyToId) } : {}),
    ...(payload.conversationId ? { context: new URL(payload.conversationId) } : {}),
  });

  const create = new Create({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: note,
    tos: payload.recipientActors.map((u) => new URL(u)),
  });

  const noteJson = await signAndSerialize(payload.actor, create) as Record<string, unknown>;

  // Inject _misskey_content for Misskey compatibility
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
