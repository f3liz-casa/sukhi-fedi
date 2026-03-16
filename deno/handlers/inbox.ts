import {
  Accept,
  Activity,
  Add,
  Announce,
  Block,
  Create,
  Delete,
  EmojiReact,
  Flag,
  Follow,
  Like,
  Move,
  Reject,
  Remove,
  Undo,
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

  if (type === "Announce") {
    const announce = await Announce.fromJsonLd(raw, { documentLoader });
    const announceJson = await announce.toJsonLd({ contextLoader: documentLoader });
    return { action: "save", object: announceJson };
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

  if (type === "Like" || type === "EmojiReact") {
    const activity: Activity = type === "Like"
      ? await Like.fromJsonLd(raw, { documentLoader })
      : await EmojiReact.fromJsonLd(raw, { documentLoader });
    const activityJson = await activity.toJsonLd({ contextLoader: documentLoader });
    return { action: "save", object: activityJson };
  }

  if (type === "Undo") {
    const undo = await Undo.fromJsonLd(raw, { documentLoader });
    const undoJson = await undo.toJsonLd({ contextLoader: documentLoader });
    return { action: "save", object: undoJson };
  }

  if (type === "Accept" || type === "Reject") {
    const activity: Activity = type === "Accept"
      ? await Accept.fromJsonLd(raw, { documentLoader })
      : await Reject.fromJsonLd(raw, { documentLoader });
    const activityJson = await activity.toJsonLd({ contextLoader: documentLoader });
    return { action: "save", object: activityJson };
  }

  if (type === "Move") {
    const move = await Move.fromJsonLd(raw, { documentLoader });
    const moveJson = await move.toJsonLd({ contextLoader: documentLoader });
    return { action: "save", object: moveJson };
  }

  if (type === "Block") {
    const block = await Block.fromJsonLd(raw, { documentLoader });
    const blockJson = await block.toJsonLd({ contextLoader: documentLoader });
    return { action: "save", object: blockJson };
  }

  if (type === "Flag") {
    const flag = await Flag.fromJsonLd(raw, { documentLoader });
    const flagJson = await flag.toJsonLd({ contextLoader: documentLoader });
    return { action: "save", object: flagJson };
  }

  if (type === "Add" || type === "Remove") {
    const activity: Activity = type === "Add"
      ? await Add.fromJsonLd(raw, { documentLoader })
      : await Remove.fromJsonLd(raw, { documentLoader });
    const activityJson = await activity.toJsonLd({ contextLoader: documentLoader });
    return { action: "save", object: activityJson };
  }

  return { action: "ignore" };
}
