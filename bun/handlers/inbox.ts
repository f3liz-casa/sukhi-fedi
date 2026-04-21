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
  getAuthenticatedDocumentLoader,
  importJwk,
  Like,
  Move,
  Reject,
  Remove,
  Undo,
  Update,
} from "@fedify/fedify";
import { cachedDocumentLoader } from "../fedify/context.ts";

export interface InboxPayload {
  raw: Record<string, unknown>;
  // Optional signing key so we can do authorized-fetch against servers
  // in Mastodon Secure Mode / Misskey auth-fetch-required mode when
  // resolving the remote actor for a Follow.
  signAs?: {
    keyId: string;
    privateJwk: Record<string, unknown>;
    publicJwk?: Record<string, unknown>;
  };
}

export type InboxInstruction =
  | { action: "save"; object: unknown }
  | { action: "save_and_reply"; save: unknown; reply: unknown; inbox: string }
  | { action: "ignore" };

export async function handleInbox(payload: InboxPayload): Promise<InboxInstruction> {
  let documentLoader = cachedDocumentLoader;
  if (payload.signAs) {
    const privateKey = await importJwk(
      payload.signAs.privateJwk as JsonWebKey,
      "private",
    );
    documentLoader = getAuthenticatedDocumentLoader({
      keyId: new URL(payload.signAs.keyId),
      privateKey,
    });
  }
  const raw = payload.raw;
  const type = raw["type"];

  if (type === "Follow") {
    console.log("[handleInbox] Follow: parsing", { hasSignAs: !!payload.signAs });
    let follow;
    try {
      follow = await Follow.fromJsonLd(raw, { documentLoader });
    } catch (e) {
      console.error("[handleInbox] Follow.fromJsonLd failed:", e);
      throw e;
    }
    const actorId = follow.actorId;
    console.log("[handleInbox] actorId=", actorId?.href);
    if (actorId == null) return { action: "ignore" };

    let remoteActor;
    try {
      remoteActor = await follow.getActor({ documentLoader });
    } catch (e) {
      console.error("[handleInbox] follow.getActor failed:", e);
      throw e;
    }
    console.log("[handleInbox] remoteActor=", remoteActor?.id?.href, "inboxId=", remoteActor?.inboxId?.href);
    if (remoteActor == null || remoteActor.inboxId == null) return { action: "ignore" };
    const inboxUrl = remoteActor.inboxId.href;

    const followeeUri = follow.objectId?.href;
    const followJson = await follow.toJsonLd({ contextLoader: documentLoader });
    return {
      action: "save_and_reply",
      save: { follow: followJson, followeeUri },
      reply: followJson,
      inbox: inboxUrl,
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
