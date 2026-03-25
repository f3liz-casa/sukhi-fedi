// api.ts — Route registry.
//
// This file's only job is to wire together sub-routers and shared middleware.
// It should never contain business logic. Add new feature modules in deno/api/
// and mount them here with app.route().
//
// Routing layout
// ─────────────────────────────────────────────────────────────
//  Public routes    → mounted directly on app  (no auth)
//  Protected routes → mounted on protectedApp  (authMiddleware)
//  Admin routes     → mounted on adminApp      (authMiddleware + is_admin)
//
// Adding a new endpoint
// ─────────────────────────────────────────────────────────────
//  Simple NATS pass-through:
//    Use createElixirHandler() in the appropriate feature module.
//    One line per route; no try/catch needed.
//
//  Creative logic (AP parsing, complex validation, streaming):
//    Write a full handler in the feature module using callElixir directly.
//    See deno/api/streaming.ts and deno/api/feeds.ts for examples.

import { Hono, type Context, type Next } from "hono";
import { type NatsConnection } from "nats";
import { makeNats } from "./lib/nats.ts";
import type { AppEnv } from "./lib/types.ts";
import { createUsersRouter } from "./api/users.ts";
import { createNotesRouter } from "./api/notes.ts";
import { createStreamingRouter } from "./api/streaming.ts";
import { createFeedsRouter } from "./api/feeds.ts";
import { createMediaRouter } from "./api/media.ts";
import { createSocialRouter } from "./api/social.ts";
import { createAdminRouter } from "./api/admin.ts";

export function createApi(nc: NatsConnection) {
  const { callElixir, createElixirHandler } = makeNats(nc);

  // ── Shared middleware ────────────────────────────────────────────────────

  const authMiddleware = async (c: Context<AppEnv>, next: Next) => {
    const auth = c.req.header("authorization");
    if (!auth) return c.json({ error: "unauthorized" }, 401);

    try {
      const token = auth.replace("Bearer ", "");
      const account = await callElixir<AppEnv["Variables"]["account"]>(
        "db.auth.verify",
        { token }
      );
      c.set("account", account);
      await next();
    } catch (err) {
      return c.json({ error: (err as Error).message }, 401);
    }
  };

  const adminMiddleware = async (c: Context<AppEnv>, next: Next) => {
    if (!c.get("account").is_admin) return c.json({ error: "forbidden" }, 403);
    await next();
  };

  // ── Public app ───────────────────────────────────────────────────────────

  const app = new Hono<AppEnv>().basePath("/api");

  // Public article reads live here (no auth), protected writes are in socialApp.
  app.get("/v1/articles",
    createElixirHandler("db.article.list", (c) => ({
      cursor: c.req.query("cursor"),
      limit: c.req.query("limit"),
    }))
  );
  app.get("/v1/articles/:id",
    createElixirHandler("db.article.get", (c) => ({ id: c.req.param("id") }), { errorStatus: 404 })
  );

  app.route("/", createUsersRouter(callElixir));
  app.route("/", createNotesRouter(callElixir));
  app.route("/", createStreamingRouter(callElixir));
  app.route("/", createFeedsRouter(callElixir));

  // ── Protected app ────────────────────────────────────────────────────────

  const protectedApp = new Hono<AppEnv>();
  protectedApp.use("*", authMiddleware);
  protectedApp.route("/", createUsersRouter(callElixir));   // /v1/me, PATCH /v1/me
  protectedApp.route("/", createNotesRouter(callElixir));   // POST/DELETE notes, likes, reactions, votes
  protectedApp.route("/", createMediaRouter(callElixir));
  protectedApp.route("/", createSocialRouter(callElixir));

  app.route("/", protectedApp);

  // ── Admin app ────────────────────────────────────────────────────────────

  const adminApp = new Hono<AppEnv>().basePath("/admin");
  adminApp.use("*", authMiddleware);
  adminApp.use("*", adminMiddleware);
  adminApp.route("/", createAdminRouter(callElixir));

  app.route("/", adminApp);

  // ── Catch-all ────────────────────────────────────────────────────────────

  app.all("*", (c: Context<AppEnv>) => c.json({ error: "not found" }, 404));

  return app;
}
