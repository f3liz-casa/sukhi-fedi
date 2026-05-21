#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Guards the one duplication that is a contract, not a coincidence:
# the `@presets` map must stay byte-identical between the gateway and
# the api plugin.
#
# The two mix projects build in separate Docker contexts (./elixir and
# ./api), so a shared library is impossible — the map is physically
# copied. But an operator sets a single `ADDON_PRESETS` env expecting it
# to mean the same thing on both nodes, so drift here is a real bug.
#
# (config.ex / repo.ex / prom_ex.ex are copied between gateway and
# delivery too, but their identity is incidental rather than
# contractual — each may legitimately diverge — so they are not guarded.)
#
# Run from the repo root: `make check`.
set -euo pipefail

gateway="elixir/lib/sukhi_fedi/addon/presets.ex"
api="api/lib/sukhi_api/addon/presets.ex"

# Pull out just the `@presets %{ ... }` literal, ignoring the module
# name and moduledoc that legitimately differ between the two files.
extract() { sed -n '/@presets %{/,/^  }/p' "$1"; }

if diff <(extract "$gateway") <(extract "$api") >/dev/null; then
  echo "presets in sync"
else
  {
    echo "presets DRIFT — @presets differs between:"
    echo "  $gateway"
    echo "  $api"
    echo
    diff <(extract "$gateway") <(extract "$api") || true
  } >&2
  exit 1
fi
