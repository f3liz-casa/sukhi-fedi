import { Hono } from "hono";
import type { AppEnv } from "../lib/types.ts";
import type { CallElixir } from "../lib/nats.ts";
import { makeCreateElixirHandler } from "../lib/nats.ts";

/**
 * Media routes — all protected (auth enforced by parent router).
 *
 *   POST /v1/media/presigned   — request a pre-signed S3 upload URL
 *   POST /v1/media             — register an uploaded media item
 *   GET  /v1/media             — list the authenticated user's media
 */
export function createMediaRouter(callElixir: CallElixir) {
  const app = new Hono<AppEnv>();
  const h = makeCreateElixirHandler(callElixir);

  app.post("/v1/media/presigned",
    h("db.media.presigned", async (c) => ({
      account_id: c.get("account").id,
      ...(await c.req.json()),
    }))
  );

  app.post("/v1/media",
    h("db.media.register", async (c) => ({
      account_id: c.get("account").id,
      ...(await c.req.json()),
    }), { status: 201 })
  );

  app.get("/v1/media",
    h("db.media.list", (c) => ({
      account_id: c.get("account").id,
      cursor: c.req.query("cursor"),
      limit: c.req.query("limit"),
    }))
  );

  return app;
}
