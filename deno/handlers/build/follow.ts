import { Follow, fetchDocumentLoader, signObject } from "@fedify/fedify";
import { getOrCreateKey } from "../../fedify/keys.ts";

export interface BuildFollowPayload {
  actor: string;
  object: string;
  activityId: string;
}

export interface BuildFollowResult {
  follow: unknown;
}

export async function handleBuildFollow(
  payload: BuildFollowPayload,
): Promise<BuildFollowResult> {
  const documentLoader = fetchDocumentLoader;
  const { privateKey, keyId } = await getOrCreateKey(payload.actor);

  const follow = new Follow({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: new URL(payload.object),
  });

  const signed = await signObject(follow, privateKey, new URL(keyId), {
    documentLoader,
  });

  const followJson = await signed.toJsonLd({ contextLoader: documentLoader });

  return { follow: followJson };
}
