import { lookupObject, isActor, fetchDocumentLoader } from "@fedify/fedify";

export interface CreateTokenPayload {
  actorUri: string;
}

export interface CreateTokenResult {
  token: string;
}

export async function handleCreateToken(
  payload: CreateTokenPayload,
): Promise<CreateTokenResult> {
  const documentLoader = fetchDocumentLoader;
  const actor = await lookupObject(payload.actorUri, { documentLoader });
  if (actor == null || !isActor(actor)) {
    throw new Error(`Could not resolve actor for URI: ${payload.actorUri}`);
  }
  const token = crypto.randomUUID();
  return { token };
}
