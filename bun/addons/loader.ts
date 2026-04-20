// SPDX-License-Identifier: AGPL-3.0-or-later
import type { BunAddon, TranslateHandler } from "./types.ts";
import mastodonApi from "./mastodon_api/manifest.ts";
import misskeyApi from "./misskey_api/manifest.ts";

const ABI_MAJOR = "1";

// Static registry. Adding a new addon = add a file under addons/<id>/
// and append it here. No filesystem scan: Bun imports are static.
const ALL: BunAddon[] = [mastodonApi, misskeyApi];

// Core-owned translate keys that addons must not override.
const CORE_TRANSLATORS = new Set([
  "note",
  "follow",
  "accept",
  "announce",
  "actor",
  "dm",
  "add",
  "remove",
]);

function parseEnabled(): "all" | Set<string> {
  const raw = process.env.ENABLED_ADDONS ?? "all";
  if (raw === "" || raw === "all") return "all";
  return new Set(raw.split(",").map((s) => s.trim()).filter(Boolean));
}

function parseDisabled(): Set<string> {
  const raw = process.env.DISABLE_ADDONS ?? "";
  return new Set(raw.split(",").map((s) => s.trim()).filter(Boolean));
}

export function enabledAddons(): BunAddon[] {
  const enabled = parseEnabled();
  const disabled = parseDisabled();

  const active = ALL.filter((a) => {
    if (disabled.has(a.id)) return false;
    if (enabled === "all") return true;
    return enabled.has(a.id);
  });

  for (const a of active) {
    const [major] = a.abi_version.split(".");
    if (major !== ABI_MAJOR) {
      throw new Error(
        `addon ${a.id} declares ABI ${a.abi_version}; core is ${ABI_MAJOR}.x — refusing to start`,
      );
    }
  }

  return active;
}

export function mergedTranslators(
  core: Record<string, TranslateHandler>,
): Record<string, TranslateHandler> {
  const out: Record<string, TranslateHandler> = { ...core };

  for (const a of enabledAddons()) {
    if (!a.translators) continue;
    for (const [key, handler] of Object.entries(a.translators)) {
      if (CORE_TRANSLATORS.has(key)) {
        throw new Error(
          `addon ${a.id} tries to override core translator '${key}'`,
        );
      }
      if (out[key] && out[key] !== handler) {
        throw new Error(
          `addon ${a.id} conflicts with existing translator '${key}'`,
        );
      }
      out[key] = handler;
    }
  }

  return out;
}
