# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Anubis with sukhi-fedi's policy + imprint baked in. Kamal pulls
# this image as the public web role; it gates `/check` and forwards
# everything else to the gateway accessory. See docs/anubis.md.
#
# CI builds this on every tag push (same workflow as gateway/api).
# To change policy: edit botPolicies.yaml or imprint.md, push a tag,
# then `kamal deploy --skip-push` to roll the new anubis image.

FROM ghcr.io/techarohq/anubis:latest

# Kamal verifies the web role image carries `service=sukhi-fedi` before
# deploying it (anti-misconfig guard). The base anubis image has no
# such label, so we add it here.
LABEL service="sukhi-fedi"

# `POLICY_FNAME` and `IMPRINT_FILE` env vars (set in config/deploy.yml)
# point at these paths.
COPY botPolicies.yaml /data/cfg/botPolicies.yaml
COPY imprint.md /data/cfg/imprint.md
