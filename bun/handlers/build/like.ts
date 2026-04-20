import { Like, signObject } from "@fedify/fedify";
import { Temporal } from "@js-temporal/polyfill";
import { cachedDocumentLoader as fetchDocumentLoader } from "../../fedify/context.ts";
import { getOrCreateKey } from "../../fedify/keys.ts";

export interface BuildLikePayload {
  actor: string;
  object: string;
  activityId: string;
  recipientInboxes: string[];
}

export interface BuildLikeResult {
  like: unknown;
  recipientInboxes: string[];
}

export async function handleBuildLike(
  payload: BuildLikePayload,
): Promise<BuildLikeResult> {
  const documentLoader = fetchDocumentLoader;
  const { privateKey, keyId } = await getOrCreateKey(payload.actor);

  const like = new Like({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: new URL(payload.object),
    published: Temporal.Now.instant(),
  });

  const signed = await signObject(like, privateKey, new URL(keyId), {
    documentLoader,
  });

  const likeJson = await signed.toJsonLd({ contextLoader: documentLoader });

  return {
    like: likeJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
