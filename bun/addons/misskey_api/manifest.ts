// SPDX-License-Identifier: AGPL-3.0-or-later
import type { BunAddon } from "../types.ts";

// Misskey-compatibility addon. Symmetric with `mastodon_api`: no
// Bun-side contributions today; REST routes live on the Elixir `api/`
// plugin node.
const misskeyApi: BunAddon = {
  id: "misskey_api",
  abi_version: "1.0",
};

export default misskeyApi;
