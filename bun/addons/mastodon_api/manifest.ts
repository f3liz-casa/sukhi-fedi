// SPDX-License-Identifier: AGPL-3.0-or-later
import type { BunAddon } from "../types.ts";

// Mastodon-compatibility addon. No Bun-side contributions yet — the
// Mastodon REST surface lives on the Elixir `api/` plugin node
// (`SukhiApi.Capabilities.*`). This manifest exists so operators can
// toggle the addon uniformly across Elixir and Bun sides via
// `ENABLED_ADDONS`, and so future Mastodon-specific NATS subjects or
// translate handlers have a place to land.
const mastodonApi: BunAddon = {
  id: "mastodon_api",
  abi_version: "1.0",
};

export default mastodonApi;
