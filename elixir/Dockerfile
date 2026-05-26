# SPDX-License-Identifier: AGPL-3.0-or-later
FROM elixir:1.16-alpine AS build

WORKDIR /app

RUN apk add --no-cache build-base git

COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force
RUN MIX_ENV=prod mix deps.get --only prod
RUN MIX_ENV=prod mix deps.compile

COPY config config
COPY lib lib
COPY priv priv

RUN MIX_ENV=prod mix release

FROM elixir:1.16-alpine

# Kamal asserts a `service` label matches `service:` in config/deploy.yml
# before accepting the image. Baking it in here keeps Kamal happy when
# we deploy via `--skip-push` from CI-built images.
LABEL service="sukhi-fedi"

WORKDIR /app

RUN apk add --no-cache libstdc++ openssl ncurses-libs

COPY --from=build /app/_build/prod/rel/sukhi_fedi ./
COPY rel/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENV MIX_ENV=prod
EXPOSE 4000

CMD ["/app/entrypoint.sh"]
