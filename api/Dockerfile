# SPDX-License-Identifier: AGPL-3.0-or-later
FROM elixir:1.16-alpine AS build

WORKDIR /app

RUN apk add --no-cache build-base git

COPY mix.exs ./
COPY mix.lock* ./
RUN mix local.hex --force && mix local.rebar --force
RUN MIX_ENV=prod mix deps.get
RUN MIX_ENV=prod mix deps.compile

COPY config config
COPY lib lib

RUN MIX_ENV=prod mix release

FROM elixir:1.16-alpine

WORKDIR /app

RUN apk add --no-cache libstdc++ openssl ncurses-libs

COPY --from=build /app/_build/prod/rel/sukhi_api ./

ENV MIX_ENV=prod

# Distributed Erlang knobs — RELEASE_DISTRIBUTION, RELEASE_NODE, and
# RELEASE_COOKIE are read by the release runtime. docker-compose supplies
# them so the gateway and this node share an Erlang cluster.
CMD ["bin/sukhi_api", "start"]
