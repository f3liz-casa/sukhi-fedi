# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Build context is the repo root so this Dockerfile can pull in both
# `web/` (SPA source) and `elixir/` (gateway source). release.yml
# passes `context: .` and `file: ./elixir/Dockerfile`.

# ── SPA build ─────────────────────────────────────────────────────────────
FROM node:20-alpine AS spa

WORKDIR /spa
COPY web/package.json web/package-lock.json* ./
RUN npm install --no-audit --no-fund

COPY web/ ./
RUN npm run build

# ── Elixir release build ──────────────────────────────────────────────────
FROM elixir:1.16-alpine AS build

WORKDIR /app

RUN apk add --no-cache build-base git

# VERSION lives at the repo root and is read at compile time by
# elixir/mix.exs and api/mix.exs. The gateway image only needs the
# elixir tree to compile, so copy it next to the mix files.
COPY VERSION ../VERSION
COPY elixir/mix.exs elixir/mix.lock ./
RUN mix local.hex --force && mix local.rebar --force
RUN MIX_ENV=prod mix deps.get --only prod
RUN MIX_ENV=prod mix deps.compile

COPY elixir/config config
COPY elixir/lib lib
COPY elixir/priv priv
COPY elixir/rel rel

# Drop the prebuilt SPA into priv/static so the release embeds it.
# Gateway's `serve_spa/1` reads `index.html` from there.
COPY --from=spa /spa/build /spa-build
RUN mkdir -p priv/static && cp -r /spa-build/. priv/static/

RUN MIX_ENV=prod mix release

# ── Runtime ───────────────────────────────────────────────────────────────
FROM elixir:1.16-alpine

# Kamal asserts a `service` label matches `service:` in config/deploy.yml
# before accepting the image. Baking it in here keeps Kamal happy when
# we deploy via `--skip-push` from CI-built images.
LABEL service="sukhi-fedi"

WORKDIR /app

RUN apk add --no-cache libstdc++ openssl ncurses-libs

COPY --from=build /app/_build/prod/rel/sukhi_fedi ./
COPY elixir/rel/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENV MIX_ENV=prod
EXPOSE 4000

CMD ["/app/entrypoint.sh"]
