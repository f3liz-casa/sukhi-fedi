import { Announce, fetchDocumentLoader, signObject } from "@fedify/fedify";
import { getOrCreateKey } from "../../fedify/keys.ts";

export interface BuildAnnouncePayload {
  actor: string;
  object: string;
  activityId: string;
  recipientInboxes: string[];
}

export interface BuildAnnounceResult {
  announce: unknown;
  recipientInboxes: string[];
}

export async function handleBuildAnnounce(
  payload: BuildAnnouncePayload,
): Promise<BuildAnnounceResult> {
  const documentLoader = fetchDocumentLoader;
  const { privateKey, keyId } = await getOrCreateKey(payload.actor);

  const announce = new Announce({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: new URL(payload.object),
    published: Temporal.Now.instant(),
  });

  const signed = await signObject(announce, privateKey, new URL(keyId), {
    documentLoader,
  });

  const announceJson = await signed.toJsonLd({ contextLoader: documentLoader });

  return {
    announce: announceJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
