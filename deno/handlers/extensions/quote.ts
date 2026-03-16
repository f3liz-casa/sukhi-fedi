import { Create, Note } from "@fedify/fedify";
import { signAndSerialize, injectDefined } from "../../fedify/utils.ts";

export interface BuildQuotePayload {
  actor: string;
  content: string;
  quoteUrl: string;
  noteId: string;
  activityId: string;
  recipientInboxes: string[];
}

export interface BuildQuoteResult {
  note: unknown;
  recipientInboxes: string[];
}

export async function handleBuildQuote(
  payload: BuildQuotePayload,
): Promise<BuildQuoteResult> {
  const note = new Note({
    id: new URL(payload.noteId),
    attribution: new URL(payload.actor),
    content: payload.content,
    published: Temporal.Now.instant(),
    quoteUrl: new URL(payload.quoteUrl),
  });
  const create = new Create({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: note,
  });
  const noteJson = await signAndSerialize(payload.actor, create) as Record<string, unknown>;
  // Inject quoteUri per FEP-044f for broader compatibility
  if (noteJson["object"] && typeof noteJson["object"] === "object") {
    injectDefined(noteJson["object"] as Record<string, unknown>, {
      quoteUri: payload.quoteUrl,
    });
  }
  return {
    note: noteJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
