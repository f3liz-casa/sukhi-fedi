import { generateCryptoKeyPair, exportJwk } from "@fedify/fedify";

export interface ActorKey {
  privateKey: CryptoKey;
  publicKey: CryptoKey;
  keyId: string;
}

// In-memory key store: actorUri -> ActorKey
const keyStore = new Map<string, ActorKey>();

export async function getOrCreateKey(actorUri: string): Promise<ActorKey> {
  const existing = keyStore.get(actorUri);
  if (existing) return existing;

  const { privateKey, publicKey } = await generateCryptoKeyPair("Ed25519");
  const keyId = `${actorUri}#main-key`;
  const entry: ActorKey = { privateKey, publicKey, keyId };
  keyStore.set(actorUri, entry);
  return entry;
}

export async function exportPublicKey(actorUri: string): Promise<unknown> {
  const key = await getOrCreateKey(actorUri);
  return await exportJwk(key.publicKey);
}
