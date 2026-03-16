import {
  Activity,
  Create,
  Delete,
  Follow,
  Update,
  fetchDocumentLoader,
} from "@fedify/fedify";

export interface InboxPayload {
  raw: Record<string, unknown>;
}

export type InboxInstruction =
  | { action: "save"; object: unknown }
  | { action: "save_and_reply"; save: unknown; reply: unknown; inbox: string }
  | { action: "ignore" };

export async function handleInbox(payload: InboxPayload): Promise<InboxInstruction> {
  const documentLoader = fetchDocumentLoader;
  const raw = payload.raw;
  const type = raw["type"];

  if (type === "Follow") {
    const follow = await Follow.fromJsonLd(raw, { documentLoader });
    const actorId = follow.actorId;
    if (actorId == null) return { action: "ignore" };

    const followJson = await follow.toJsonLd({ contextLoader: documentLoader });
    return {
      action: "save_and_reply",
      save: { follow: followJson },
      reply: followJson,
      inbox: actorId.href,
    };
  }

  if (type === "Create" || type === "Update" || type === "Delete") {
    let activity: Activity;
    if (type === "Create") {
      activity = await Create.fromJsonLd(raw, { documentLoader });
    } else if (type === "Update") {
      activity = await Update.fromJsonLd(raw, { documentLoader });
    } else {
      activity = await Delete.fromJsonLd(raw, { documentLoader });
    }
    const activityJson = await activity.toJsonLd({ contextLoader: documentLoader });
    return { action: "save", object: activityJson };
  }

  return { action: "ignore" };
}
