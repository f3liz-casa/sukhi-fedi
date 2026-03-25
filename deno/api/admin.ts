import { Hono } from "hono";
import type { AppEnv } from "../lib/types.ts";
import type { CallElixir } from "../lib/nats.ts";
import { makeCreateElixirHandler } from "../lib/nats.ts";

/**
 * Admin routes — mounted under /api/admin.
 *
 * All routes require auth + is_admin (enforced by middleware in api.ts).
 *
 *   GET    /reports
 *   POST   /reports/:id/resolve
 *   POST   /instance-blocks
 *   DELETE /instance-blocks/:domain
 *   GET    /instance-blocks
 *   POST   /accounts/:id/suspend
 *   DELETE /accounts/:id/suspend
 *   POST   /emojis
 *   DELETE /emojis/:id
 */
export function createAdminRouter(callElixir: CallElixir) {
  const app = new Hono<AppEnv>();
  const h = makeCreateElixirHandler(callElixir);

  app.get("/reports",
    h("db.admin.report.list", (c) => ({ status: c.req.query("status") }))
  );

  app.post("/reports/:id/resolve",
    h("db.admin.report.resolve", (c) => ({
      id: c.req.param("id"),
      admin_id: c.get("account").id,
    }))
  );

  app.post("/instance-blocks",
    h("db.admin.instance_block.create", async (c) => ({
      admin_id: c.get("account").id,
      ...(await c.req.json()),
    }))
  );

  app.delete("/instance-blocks/:domain",
    h("db.admin.instance_block.delete", (c) => ({
      domain: c.req.param("domain"),
    }))
  );

  app.get("/instance-blocks",
    h("db.admin.instance_block.list", () => ({}))
  );

  app.post("/accounts/:id/suspend",
    h("db.admin.account.suspend", async (c) => ({
      id: c.req.param("id"),
      admin_id: c.get("account").id,
      reason: (await c.req.json()).reason,
    }))
  );

  app.delete("/accounts/:id/suspend",
    h("db.admin.account.unsuspend", (c) => ({ id: c.req.param("id") }))
  );

  app.post("/emojis",
    h("db.admin.emoji.create", (c) => c.req.json(), { status: 201 })
  );

  app.delete("/emojis/:id",
    h("db.admin.emoji.delete", (c) => ({ id: c.req.param("id") }), { status: 204 })
  );

  return app;
}
