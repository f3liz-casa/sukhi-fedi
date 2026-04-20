import { generateCryptoKeyPair, exportJwk, Person, fetchDocumentLoader } from "@fedify/fedify";

export interface BuildActorPayload {
  username: string;
  displayName?: string;
  summary?: string;
  actorUri: string;
  keyId: string;
  inboxUri: string;
}

export interface BuildActorResult {
  actor: unknown;
  privateKeyJwk: unknown;
  publicKeyJwk: unknown;
}

export async function handleBuildActor(
  payload: BuildActorPayload,
): Promise<BuildActorResult> {
  const documentLoader = fetchDocumentLoader;
  const { privateKey, publicKey } = await generateCryptoKeyPair("Ed25519");

  const person = new Person({
    id: new URL(payload.actorUri),
    name: payload.displayName ?? payload.username,
    summary: payload.summary ?? null,
    inbox: new URL(payload.inboxUri),
    preferredUsername: payload.username,
  });

  const actorJson = await person.toJsonLd({ contextLoader: documentLoader });

  return {
    actor: actorJson,
    privateKeyJwk: await exportJwk(privateKey),
    publicKeyJwk: await exportJwk(publicKey),
  };
}
