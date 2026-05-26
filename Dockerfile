# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Wrapper Dockerfile so `kamal setup` / `kamal deploy` succeed.
# Kamal 2 has no "use a pre-built image, skip the build entirely"
# mode — it always runs `docker buildx build` against a Dockerfile.
# This file re-FROMs the gateway image already produced by
# `.github/workflows/release.yml`, so the build is effectively a
# no-op (no new layers) and only a tiny manifest is pushed.
#
# To pin a specific patch version instead of the rolling :v0 tag:
#   kamal deploy --build-arg GATEWAY_VERSION=v0.1.37
# Or edit the default below.

ARG GATEWAY_VERSION=v0
FROM ghcr.io/f3liz-casa/sukhi-fedi-gateway:${GATEWAY_VERSION}
