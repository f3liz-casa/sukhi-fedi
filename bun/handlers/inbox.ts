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
  // Public host of this instance (e.g. "watch-mjw.f3liz.casa"). Used
  // to mint the Accept activity's own `id` — remote servers expect
  // it to be a resolvable URL under our domain.
  selfDomain?: string;
}

export type InboxInstruction =
  | { action: "save"; object: unknown }
  | { action: "save_and_reply"; save: unknown; reply: unknown; inbox: string }
  | { action: "ignore" };

export async function handleInbox(payload: InboxPayload): Promise<InboxInstruction> {
  // Two loaders:
  //   contextLoader — unauthenticated. Fedify's default handles JSON-LD
  //     context resolution (activitystreams, security/v1, identity/v1,
  //     …) including the legacy redirect chains like w3id.org → web-
  //     payments.org. Signing these GETs confuses hosts that don't
  //     expect HTTP-Signature on context URLs.
  //   actorLoader   — signed when the receiving actor has a keypair, so
  //     Mastodon Secure Mode / Misskey auth-fetch-required servers
  //     return 200 for actor dereference instead of 401.
  const contextLoader = cachedDocumentLoader;
  let actorLoader = contextLoader;
  if (payload.signAs) {
    const privateKey = await importJwk(
      payload.signAs.privateJwk as JsonWebKey,
      "private",
    );
    actorLoader = getAuthenticatedDocumentLoader({
      keyId: new URL(payload.signAs.keyId),
      privateKey,
    });
  }
  const raw = payload.raw;
  const type = raw["type"];

  if (type === "Follow") {
    const follow = await Follow.fromJsonLd(raw, { documentLoader: contextLoader });
    if (follow.actorId == null || follow.objectId == null) return { action: "ignore" };

    const remoteActor = await follow.getActor({ documentLoader: actorLoader });
    if (remoteActor == null || remoteActor.inboxId == null) return { action: "ignore" };
    const inboxUrl = remoteActor.inboxId.href;

    const followeeUri = follow.objectId.href;
    const followJson = await follow.toJsonLd({ contextLoader });

    // Build an Accept(Follow) to send back. The follower is waiting for
    // this — without it their pending-follow state never resolves.
    const selfDomain = payload.selfDomain ?? new URL(followeeUri).host;
    const accept = new Accept({
      id: new URL(`https://${selfDomain}/activities/accept/${crypto.randomUUID()}`),
      actor: follow.objectId,
      object: follow,
    });
    const acceptJson = await accept.toJsonLd({ contextLoader });

    return {
      action: "save_and_reply",
      save: { follow: followJson, followeeUri },
      reply: acceptJson,
      inbox: inboxUrl,
    };
  }

  if (type === "Announce") {
    const announce = await Announce.fromJsonLd(raw, { documentLoader: contextLoader });
    const announceJson = await announce.toJsonLd({ contextLoader });
    return { action: "save", object: announceJson };
  }
  if (type === "Create" || type === "Update" || type === "Delete") {
    let activity: Activity;
    if (type === "Create") {
      activity = await Create.fromJsonLd(raw, { documentLoader: contextLoader });
    } else if (type === "Update") {
      activity = await Update.fromJsonLd(raw, { documentLoader: contextLoader });
    } else {
      activity = await Delete.fromJsonLd(raw, { documentLoader: contextLoader });
    }
    const activityJson = await activity.toJsonLd({ contextLoader });
    return { action: "save", object: activityJson };
  }

  if (type === "Like" || type === "EmojiReact") {
    const activity: Activity = type === "Like"
      ? await Like.fromJsonLd(raw, { documentLoader: contextLoader })
      : await EmojiReact.fromJsonLd(raw, { documentLoader: contextLoader });
    const activityJson = await activity.toJsonLd({ contextLoader });
    return { action: "save", object: activityJson };
  }

  if (type === "Undo") {
    const undo = await Undo.fromJsonLd(raw, { documentLoader: contextLoader });
    const undoJson = await undo.toJsonLd({ contextLoader });
    return { action: "save", object: undoJson };
  }

  if (type === "Accept" || type === "Reject") {
    const activity: Activity = type === "Accept"
      ? await Accept.fromJsonLd(raw, { documentLoader: contextLoader })
      : await Reject.fromJsonLd(raw, { documentLoader: contextLoader });
    const activityJson = await activity.toJsonLd({ contextLoader });
    return { action: "save", object: activityJson };
  }

  if (type === "Move") {
    const move = await Move.fromJsonLd(raw, { documentLoader: contextLoader });
    const moveJson = await move.toJsonLd({ contextLoader });
    return { action: "save", object: moveJson };
  }

  if (type === "Block") {
    const block = await Block.fromJsonLd(raw, { documentLoader: contextLoader });
    const blockJson = await block.toJsonLd({ contextLoader });
    return { action: "save", object: blockJson };
  }

  if (type === "Flag") {
    const flag = await Flag.fromJsonLd(raw, { documentLoader: contextLoader });
    const flagJson = await flag.toJsonLd({ contextLoader });
    return { action: "save", object: flagJson };
  }

  if (type === "Add" || type === "Remove") {
    const activity: Activity = type === "Add"
      ? await Add.fromJsonLd(raw, { documentLoader: contextLoader })
      : await Remove.fromJsonLd(raw, { documentLoader: contextLoader });
    const activityJson = await activity.toJsonLd({ contextLoader });
    return { action: "save", object: activityJson };
  }

  return { action: "ignore" };
}
