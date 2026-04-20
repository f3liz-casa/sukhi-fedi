import { fetchDocumentLoader } from "@fedify/fedify";

const documentCache = new Map<string, Awaited<ReturnType<typeof fetchDocumentLoader>>>();

export const cachedDocumentLoader: typeof fetchDocumentLoader = async (url: string) => {
  const hit = documentCache.get(url);
  if (hit) return hit;
  const result = await fetchDocumentLoader(url);
  documentCache.set(url, result);
  return result;
};
