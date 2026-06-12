# sukhi-fedi

Read first:

- `docs/ARCHITECTURE.md` — canonical; where processes run and why.
- `docs/CODE_STYLE.md` — the separation style; where concerns live.

The one rule from CODE_STYLE.md: **every security or performance
property lives in exactly one place, and structure routes all paths
through it.** Check once at the boundary, trust inside; pay once per
batch, never per item. Before finishing any change, walk the
checklist in CODE_STYLE.md §7.

Practical notes:

- Tests: `make test-pglite` (no docker). Local `mix` needs
  `mise exec elixir@1.20.0 --` (shell default is 1.19.5).
- TypeScript in `bun/` is checked with `bun run check` (type-only).
- Every source file starts with
  `# SPDX-License-Identifier: AGPL-3.0-or-later`.
