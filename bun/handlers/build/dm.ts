// SPDX-License-Identifier: AGPL-3.0-or-later
import { Create, Note } from "@fedify/fedify/vocab";
import { nowInstant } from "../../fedify/temporal.ts";
import { injectAttachments, injectMisskey, signAndSerialize, type AttachmentDescriptor, type SignedPayload } from "../../fedify/utils.ts";
import { resolveAudience } from "../../fedify/addressing.ts";

export interface BuildDmPayload extends SignedPayload {
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
  /** Media attachments, in gallery order. Optional. */
  attachments?: AttachmentDescriptor[];
}

export interface BuildDmResult {
  note: unknown;
  recipientInboxes: string[];
}

export async function handleBuildDm(payload: BuildDmPayload): Promise<BuildDmResult> {
  const audience = resolveAudience({ kind: "direct", actors: payload.recipientActors });

  const note = new Note({
    id: new URL(payload.noteId),
    attribution: new URL(payload.actor),
    content: payload.content,
    published: nowInstant(),
    tos: audience.tos,
    ccs: audience.ccs,
    ...(payload.inReplyToId ? { replyTarget: new URL(payload.inReplyToId) } : {}),
    ...(payload.conversationId ? { context: new URL(payload.conversationId) } : {}),
  });

  const create = new Create({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: note,
    tos: audience.tos,
    ccs: audience.ccs,
  });

  const noteJson = await signAndSerialize(payload, create);
  injectMisskey(noteJson, payload.content);
  injectAttachments(noteJson, payload.attachments);

  return {
    note: noteJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
