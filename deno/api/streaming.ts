import { Hono, type Context } from "hono";
import type { AppEnv } from "../lib/types.ts";
import type { CallElixir } from "../lib/nats.ts";

/**
 * Streaming delegation — Idea 3: Proxy Hand-off Pattern.
 *
 * Deno owns auth/logic; Elixir owns the long-lived SSE socket.
 *
 * Flow:
 *   1. Client → GET /api/v1/streaming/:urn  (hits Elixir, proxied to Deno)
 *   2. Deno validates auth for protected streams (e.g. "home")
 *   3. Deno responds 200 with header  X-Delegate-To: Streaming
 *   4. Elixir ProxyPlug detects the header and hands the connection to
 *      StreamingController, which holds the SSE socket.
 *
 * To add a new stream type:
 *   - Add an `else if (urn === "my_new_stream")` block with whatever
 *     auth/permission check is needed, then fall through to the
 *     `X-Delegate-To` response. That's all.
 */
export function createStreamingRouter(callElixir: CallElixir) {
  const app = new Hono<AppEnv>();

  app.get("/v1/streaming/:urn", async (c: Context<AppEnv>) => {
    const urn = c.req.param("urn");

    if (urn === "home") {
      // Home feed requires a valid Bearer token.
      const auth = c.req.header("authorization");
      if (!auth) return c.json({ error: "unauthorized" }, 401);

      try {
        await callElixir("db.auth.verify", { token: auth.replace("Bearer ", "") });
      } catch {
        return c.json({ error: "unauthorized" }, 401);
      }
    }

    // Signal ProxyPlug to hand the TCP socket to StreamingController.
    // Elixir will never forward this body to the client — it intercepts
    // the header and takes over the connection directly.
    c.header("X-Delegate-To", "Streaming");
    return c.body(null, 200);
  });

  return app;
}
