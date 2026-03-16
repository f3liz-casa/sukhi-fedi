import { createFederation, MemoryKvStore } from "@fedify/fedify";

export const federation = createFederation<void>({
  kv: new MemoryKvStore(),
});
