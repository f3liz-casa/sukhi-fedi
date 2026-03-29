# SPDX-License-Identifier: AGPL-3.0-or-later
FROM denoland/deno:2.3.1

WORKDIR /app

COPY deno.json deno.lock ./
RUN deno install --frozen

COPY . .

CMD ["task", "start"]
