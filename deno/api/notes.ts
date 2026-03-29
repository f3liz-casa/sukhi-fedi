import { Hono } from "hono";
import type { AppEnv } from "../lib/types.ts";
import type { CallElixir } from "../lib/nats.ts";
import { makeCreateElixirHandler } from "../lib/nats.ts";

/**
 * Note routes.
 *
 * Public:
 *   GET /v1/notes/:id
 *   GET /v1/notes/:id/reactions
 *   GET /v1/emojis
 *
 * Protected (auth enforced by parent router):
 *   POST   /v1/notes
 *   DELETE /v1/notes/:id
 *   POST   /v1/notes/:id/like
 *   DELETE /v1/notes/:id/like
 *   PUT    /v1/notes/:id/reactions
 *   DELETE /v1/notes/:id/reactions/:emoji
 *   POST   /v1/notes/:id/vote
 *   POST   /v1/reports
 */
export function createNotesRouter(callElixir: CallElixir) {
  const app = new Hono<AppEnv>();
  const h = makeCreateElixirHandler(callElixir);

  // ── Public ────────────────────────────────────────────────────────────────

  app.get("/v1/notes/:id",
    h("db.note.get", (c) => ({ id: c.req.param("id") }), { errorStatus: 404 })
  );

  app.get("/v1/notes/:id/reactions",
    h("db.note.reaction.list", (c) => ({ note_id: c.req.param("id") }), { errorStatus: 404 })
  );

  app.get("/v1/emojis",
    h("db.emoji.list", () => ({}))
  );

  // ── Protected ─────────────────────────────────────────────────────────────

  app.post("/v1/notes",
    h("db.note.create", async (c) => ({
      account_id: c.get("account").id,
      ...(await c.req.json()),
    }), { status: 201 })
  );

  app.delete("/v1/notes/:id",
    h("db.note.delete", (c) => ({
      id: c.req.param("id"),
      account_id: c.get("account").id,
    }), { status: 204 })
  );

  app.post("/v1/notes/:id/like",
    h("db.note.like", (c) => ({
      account_id: c.get("account").id,
      note_id: c.req.param("id"),
    }), { status: 201 })
  );

  app.delete("/v1/notes/:id/like",
    h("db.note.unlike", (c) => ({
      account_id: c.get("account").id,
      note_id: c.req.param("id"),
    }), { status: 204 })
  );

  app.put("/v1/notes/:id/reactions",
    h("db.note.reaction.add", async (c) => ({
      account_id: c.get("account").id,
      note_id: c.req.param("id"),
      emoji: (await c.req.json()).emoji,
    }), { status: 201 })
  );

  app.delete("/v1/notes/:id/reactions/:emoji",
    h("db.note.reaction.remove", (c) => ({
      account_id: c.get("account").id,
      note_id: c.req.param("id"),
      emoji: decodeURIComponent(c.req.param("emoji") ?? ""),
    }), { status: 204 })
  );

  app.post("/v1/notes/:id/vote",
    h("db.note.poll.vote", async (c) => ({
      account_id: c.get("account").id,
      note_id: c.req.param("id"),
      choices: (await c.req.json()).choices,
    }), { status: 201 })
  );

  app.post("/v1/reports",
    h("db.moderation.report", async (c) => ({
      account_id: c.get("account").id,
      ...(await c.req.json()),
    }), { status: 201 })
  );

  app.post("/v1/notes/:id/pin",
    h("db.note.pin", (c) => ({
      account_id: c.get("account").id,
      note_id: c.req.param("id"),
    }), { status: 200 })
  );

  app.delete("/v1/notes/:id/pin",
    h("db.note.unpin", (c) => ({
      account_id: c.get("account").id,
      note_id: c.req.param("id"),
    }), { status: 204 })
  );

  return app;
}
