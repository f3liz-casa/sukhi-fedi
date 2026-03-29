// SPDX-License-Identifier: MPL-2.0
import { Hono } from "hono";
import type { AppEnv } from "../lib/types.ts";
import type { CallElixir } from "../lib/nats.ts";
import { makeCreateElixirHandler } from "../lib/nats.ts";

/**
 * Direct message / conversation routes.
 *
 * All routes require authentication (enforced by protectedApp in api.ts).
 *
 *   POST   /v1/conversations               Create a new DM thread or reply
 *   GET    /v1/conversations               List conversation threads for the user
 *   GET    /v1/conversations/:id           Get messages in a conversation
 */
export function createConversationsRouter(callElixir: CallElixir) {
  const app = new Hono<AppEnv>();
  const h = makeCreateElixirHandler(callElixir);

  app.post(
    "/v1/conversations",
    h(
      "db.dm.create",
      async (c) => ({
        account_id: c.get("account").id,
        ...(await c.req.json()),
      }),
      { status: 201 },
    ),
  );

  app.get(
    "/v1/conversations",
    h("db.dm.list", (c) => ({
      account_id: c.get("account").id,
      limit: c.req.query("limit"),
    })),
  );

  app.get(
    "/v1/conversations/:id",
    h(
      "db.dm.conversation.get",
      (c) => ({
        account_id: c.get("account").id,
        conversation_ap_id: decodeURIComponent(c.req.param("id")),
        limit: c.req.query("limit"),
      }),
      { errorStatus: 403 },
    ),
  );

  return app;
}
