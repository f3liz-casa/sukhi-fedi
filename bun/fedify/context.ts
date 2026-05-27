import { getDocumentLoader, type DocumentLoader, type RemoteDocument } from "@fedify/fedify/runtime";

const defaultLoader: DocumentLoader = getDocumentLoader();
const documentCache = new Map<string, RemoteDocument>();

export const cachedDocumentLoader: DocumentLoader = async (url) => {
  const hit = documentCache.get(url);
  if (hit) return hit;
  const result = await defaultLoader(url);
  documentCache.set(url, result);
  return result;
};
