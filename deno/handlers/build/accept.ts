import { Accept, Follow, fetchDocumentLoader, signObject } from "@fedify/fedify";
import { getOrCreateKey } from "../../fedify/keys.ts";

export interface BuildAcceptPayload {
  actor: string;
  followActivityId: string;
  followActor: string;
  activityId: string;
}

export interface BuildAcceptResult {
  accept: unknown;
}

export async function handleBuildAccept(
  payload: BuildAcceptPayload,
): Promise<BuildAcceptResult> {
  const documentLoader = fetchDocumentLoader;
  const { privateKey, keyId } = await getOrCreateKey(payload.actor);

  const followObject = new Follow({
    id: new URL(payload.followActivityId),
    actor: new URL(payload.followActor),
    object: new URL(payload.actor),
  });

  const accept = new Accept({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: followObject,
  });

  const signed = await signObject(accept, privateKey, new URL(keyId), {
    documentLoader,
  });

  const acceptJson = await signed.toJsonLd({ contextLoader: documentLoader });

  return { accept: acceptJson };
}
