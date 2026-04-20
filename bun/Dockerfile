# SPDX-License-Identifier: AGPL-3.0-or-later
FROM oven/bun:1-alpine

WORKDIR /app

COPY package.json ./
RUN bun install --frozen-lockfile || bun install

COPY . .

CMD ["bun", "run", "main.ts"]
