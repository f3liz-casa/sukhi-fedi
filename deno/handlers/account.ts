import { generateCryptoKeyPair, exportJwk } from "@fedify/fedify";

export interface CreateAccountPayload {
  username: string;
  displayName?: string;
  summary?: string;
  actorUri: string;
  keyId: string;
  inboxUri: string;
}

export interface CreateAccountResult {
  privateKeyJwk: unknown;
  publicKeyJwk: unknown;
}

export async function handleCreateAccount(
  payload: CreateAccountPayload,
): Promise<CreateAccountResult> {
  const { privateKey, publicKey } = await generateCryptoKeyPair("Ed25519");
  return {
    privateKeyJwk: await exportJwk(privateKey),
    publicKeyJwk: await exportJwk(publicKey),
  };
}
