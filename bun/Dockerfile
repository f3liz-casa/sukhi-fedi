# SPDX-License-Identifier: AGPL-3.0-or-later
FROM oven/bun:1-alpine

WORKDIR /app

COPY package.json bun.lock ./
RUN bun install --frozen-lockfile || bun install

COPY . .

CMD ["bun", "run", "services/fedify_service.ts"]
