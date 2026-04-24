import {
  Accept,
  Follow,
  getAuthenticatedDocumentLoader,
  importJwk,
} from "@fedify/fedify";
import { cachedDocumentLoader } from "../fedify/context.ts";
import { classifyActivity, KIND_PARSERS } from "../fedify/activity_kinds.ts";
import { logJson, newTrace, type Trace } from "../fedify/trace.ts";

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
  // Upstream correlation id (Phase 2 will wire this through NATS
  // headers; accepting it now keeps the payload shape stable).
  correlationId?: string;
}

export type InboxInstruction =
  | { action: "save"; object: unknown }
  | { action: "save_and_reply"; save: unknown; reply: unknown; inbox: string }
  | { action: "ignore" };

export async function handleInbox(payload: InboxPayload): Promise<InboxInstruction> {
  const trace: Trace = payload.correlationId
    ? { correlationId: payload.correlationId }
    : newTrace();
  const started = performance.now();

  // Two loaders:
  //   contextLoader — unauthenticated. Fedify's default handles JSON-LD
  //     context resolution (activitystreams, security/v1, identity/v1,
  //     …) including the legacy redirect chains like w3id.org → web-
  //     payments.org. Signing these GETs confuses hosts that don't
  //     expect HTTP-Signature on context URLs.
  //   actorLoader   — signed when the receiving actor has a keypair, so
  //     Mastodon Secure Mode / Misskey auth-fetch-required servers
  //     return 200 for actor dereference instead of 401.
  // Phase 2 will move this split into fedify/loaders.ts with a typed
  // LoaderMode enum.
  const contextLoader = cachedDocumentLoader;
  let actorLoader: typeof cachedDocumentLoader = contextLoader;
  if (payload.signAs) {
    const privateKey = await importJwk(
      payload.signAs.privateJwk as Parameters<typeof importJwk>[0],
      "private",
    );
    actorLoader = getAuthenticatedDocumentLoader({
      keyId: new URL(payload.signAs.keyId),
      privateKey,
    }) as typeof cachedDocumentLoader;
  }

  const raw = payload.raw;
  const kind = classifyActivity(raw);
  const rawActivityId = typeof raw["id"] === "string" ? (raw["id"] as string) : undefined;
  const rawActor = typeof raw["actor"] === "string" ? (raw["actor"] as string) : undefined;

  const done = (result: InboxInstruction, extra?: Record<string, unknown>) => {
    const ms = Math.round(performance.now() - started);
    logJson(trace, "info", "inbox.done", {
      activity_type: kind,
      activity_id: rawActivityId,
      actor: rawActor,
      action: result.action,
      ms,
      ...extra,
    });
    return result;
  };

  if (kind === "unknown") {
    // Phase 3 will persist these to an unknown_activities table so we
    // can learn about new activity shapes. For now, log and skip.
    logJson(trace, "warn", "inbox.unknown_type", {
      raw_type: raw["type"],
      activity_id: rawActivityId,
      actor: rawActor,
    });
    return done({ action: "ignore" });
  }

  if (kind === "Follow") {
    const follow = await Follow.fromJsonLd(raw, { documentLoader: contextLoader });
    if (follow.actorId == null || follow.objectId == null) {
      logJson(trace, "warn", "inbox.follow_missing_ids", { activity_id: rawActivityId });
      return done({ action: "ignore" });
    }

    const remoteActor = await follow.getActor({ documentLoader: actorLoader });
    if (remoteActor == null || remoteActor.inboxId == null) {
      logJson(trace, "warn", "inbox.follow_unresolved_actor", {
        activity_id: rawActivityId,
        actor: follow.actorId.href,
      });
      return done({ action: "ignore" });
    }
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

    return done(
      {
        action: "save_and_reply",
        save: { follow: followJson, followeeUri },
        reply: acceptJson,
        inbox: inboxUrl,
      },
      { target_inbox: inboxUrl },
    );
  }

  const parser = KIND_PARSERS[kind];
  const activity = await parser(raw, { documentLoader: contextLoader });
  const activityJson = await activity.toJsonLd({ contextLoader });
  return done({ action: "save", object: activityJson });
}
