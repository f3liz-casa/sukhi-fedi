import { Hono, type Context } from "hono";
import type { AppEnv } from "../lib/types.ts";
import type { CallElixir } from "../lib/nats.ts";
import { makeCreateElixirHandler } from "../lib/nats.ts";

/**
 * User/account routes.
 *
 * Public:
 *   GET /v1/users/:username
 *   GET /v1/users/:username/notes
 *   GET /v1/users/:username/followers
 *   GET /v1/users/:username/following
 *
 * Protected (authMiddleware applied in api.ts before mounting):
 *   GET    /v1/me
 *   PATCH  /v1/me
 *   POST   /v1/accounts
 *   POST   /v1/auth/session
 */
export function createUsersRouter(callElixir: CallElixir) {
  const app = new Hono<AppEnv>();
  const h = makeCreateElixirHandler(callElixir);

  // ── Public ────────────────────────────────────────────────────────────────

  app.post("/v1/accounts",
    h("db.account.create", (c) => c.req.json(), { status: 201 })
  );

  app.post("/v1/auth/session",
    h("db.auth.session", (c) => c.req.json(), { errorStatus: 401 })
  );

  app.get("/v1/users/:username",
    h("db.account.get", (c) => ({ username: c.req.param("username") }), { errorStatus: 404 })
  );

  app.get("/v1/users/:username/notes",
    h("db.account.notes", (c) => ({
      username: c.req.param("username"),
      cursor: c.req.query("cursor"),
      limit: c.req.query("limit"),
    }), { errorStatus: 404 })
  );

  app.get("/v1/users/:username/followers",
    h("db.account.followers", (c) => ({
      username: c.req.param("username"),
      cursor: c.req.query("cursor"),
      limit: c.req.query("limit"),
    }), { errorStatus: 404 })
  );

  app.get("/v1/users/:username/following",
    h("db.account.following", (c) => ({
      username: c.req.param("username"),
      cursor: c.req.query("cursor"),
      limit: c.req.query("limit"),
    }), { errorStatus: 404 })
  );

  // ── Protected (auth already enforced by the parent router) ────────────────

  app.get("/v1/me", (c: Context<AppEnv>) => c.json(c.get("account")));

  app.patch("/v1/me",
    h("db.account.update", async (c) => ({
      id: c.get("account").id,
      ...(await c.req.json()),
    }))
  );

  return app;
}
