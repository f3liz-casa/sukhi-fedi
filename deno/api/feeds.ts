import { Hono, type Context } from "hono";
import type { AppEnv } from "../lib/types.ts";
import type { CallElixir } from "../lib/nats.ts";

/**
 * Feed routes — mixed public/protected logic that doesn't fit the simple
 * factory pattern because the home feed requires inline auth.
 *
 *   GET /v1/feeds/:urn   (public for local/public; auth-gated for home)
 */
export function createFeedsRouter(callElixir: CallElixir) {
  const app = new Hono<AppEnv>();

  // The home feed requires an auth token, but local/public are open.
  // This is a good example of "creative logic" that warrants a full handler
  // instead of the factory shortcut.
  app.get("/v1/feeds/:urn", async (c: Context<AppEnv>) => {
    const urn = c.req.param("urn");

    try {
      let account_id: string | undefined;

      if (urn === "home") {
        const auth = c.req.header("authorization");
        if (!auth) return c.json({ error: "unauthorized" }, 401);

        const account = await callElixir<{ id: string }>("db.auth.verify", {
          token: auth.replace("Bearer ", ""),
        });
        account_id = account.id;
      }

      const result = await callElixir("db.feed.get", {
        urn,
        account_id,
        cursor: c.req.query("cursor"),
        limit: c.req.query("limit"),
      });

      return c.json(result);
    } catch (err) {
      return c.json({ error: (err as Error).message }, 404);
    }
  });

  return app;
}
