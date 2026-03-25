import { Hono } from "hono";
import type { AppEnv } from "../lib/types.ts";
import type { CallElixir } from "../lib/nats.ts";
import { makeCreateElixirHandler } from "../lib/nats.ts";

/**
 * Social interaction routes — all protected (auth enforced by parent router).
 *
 *   PATCH  /v1/relationships/:id
 *   GET    /v1/bookmarks
 *   POST   /v1/bookmarks
 *   DELETE /v1/bookmarks/:note_id
 *   GET    /v1/articles
 *   GET    /v1/articles/:id
 *   POST   /v1/articles
 */
export function createSocialRouter(callElixir: CallElixir) {
  const app = new Hono<AppEnv>();
  const h = makeCreateElixirHandler(callElixir);

  app.patch("/v1/relationships/:id",
    h("db.social.relationship.update", async (c) => ({
      account_id: c.get("account").id,
      target_id: c.req.param("id"),
      ...(await c.req.json()),
    }))
  );

  app.get("/v1/bookmarks",
    h("db.bookmark.list", (c) => ({
      account_id: c.get("account").id,
      cursor: c.req.query("cursor"),
      limit: c.req.query("limit"),
    }))
  );

  app.post("/v1/bookmarks",
    h("db.bookmark.create", async (c) => ({
      account_id: c.get("account").id,
      note_id: (await c.req.json()).note_id,
    }), { status: 201 })
  );

  app.delete("/v1/bookmarks/:note_id",
    h("db.bookmark.delete", (c) => ({
      account_id: c.get("account").id,
      note_id: c.req.param("note_id"),
    }), { status: 204 })
  );

  // Articles are public for reads, protected for writes.
  // Public reads are registered in api.ts directly (no auth needed).
  app.post("/v1/articles",
    h("db.article.create", async (c) => ({
      account_id: c.get("account").id,
      ...(await c.req.json()),
    }), { status: 201 })
  );

  return app;
}
