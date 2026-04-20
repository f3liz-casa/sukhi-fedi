import { createFederation, MemoryKvStore, fetchDocumentLoader } from "@fedify/fedify";

export const federation = createFederation<void>({
  kv: new MemoryKvStore(),
});

const documentCache = new Map<string, Awaited<ReturnType<typeof fetchDocumentLoader>>>();

export const cachedDocumentLoader: typeof fetchDocumentLoader = async (url: string) => {
  const hit = documentCache.get(url);
  if (hit) return hit;
  const result = await fetchDocumentLoader(url);
  documentCache.set(url, result);
  return result;
};
