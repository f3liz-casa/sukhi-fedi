import { lookupObject, isActor, fetchDocumentLoader } from "@fedify/fedify";

export interface AuthPayload {
  token: string;
}

export interface AuthResult {
  actor: unknown;
}

export async function handleAuth(payload: AuthPayload): Promise<AuthResult> {
  const documentLoader = fetchDocumentLoader;
  const actor = await lookupObject(payload.token, { documentLoader });
  if (actor == null || !isActor(actor)) {
    throw new Error(`Could not resolve actor for token: ${payload.token}`);
  }
  const actorJson = await actor.toJsonLd({ contextLoader: documentLoader });
  return { actor: actorJson };
}
