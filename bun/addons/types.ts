// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Bun-side addon contract.
//
// An addon contributes extra entries for the `fedify.translate.v1`
// dispatch table (via `translators`). Addons are loaded by
// `addons/loader.ts`, filtered against the `ENABLED_ADDONS` env var
// (comma-separated ids, or "all").

export type TranslateHandler = (payload: unknown) => Promise<unknown>;

export interface BunAddon {
  id: string;
  abi_version: string;
  // Extra TRANSLATORS entries. Keys must be namespaced as
  // `<addon_id>.<type>` to avoid collisions with core (`note`, `follow`,
  // `accept`, `announce`, `actor`, `dm`, `add`, `remove`).
  translators?: Record<string, TranslateHandler>;
}
