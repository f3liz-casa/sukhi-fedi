# SPDX-License-Identifier: AGPL-3.0-or-later
import Config

config :sukhi_api,
  domain: "localhost:4000",
  title: "sukhi-fedi",
  # :all (default) activates every compiled capability. Swap in a list
  # of module names to narrow the node's surface — useful when running
  # multiple specialised plugin nodes (e.g. admin-only) under different
  # RELEASE_NODE names.
  enabled_capabilities: :all

import_config "#{config_env()}.exs"
