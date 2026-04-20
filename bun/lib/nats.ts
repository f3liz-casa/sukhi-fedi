// NATS RPC helpers for Deno ↔ Elixir communication.
//
// makeNats(nc) returns two tools:
//
//   callElixir(subject, payload) — raw NATS request/reply, typed
//
//   createElixirHandler(subject, extractor, opts?) — route factory that
//     eliminates boilerplate. Use this for any route that is purely a
//     pass-through to Elixir. For routes with creative logic (AP parsing,
//     complex validation, streaming hand-off, etc.) write a full handler.
//
// Usage:
//   const { callElixir, createElixirHandler } = makeNats(nc);
//
//   app.get("/v1/users/:username",
//     createElixirHandler("db.account.get", (c) => ({
//       username: c.req.param("username"),
//     }))
//   );

import { type Context } from "hono";
import { type NatsConnection } from "nats";
import type { AppEnv } from "./types.ts";

// ─── Core RPC ────────────────────────────────────────────────────────────────

export type CallElixir = <T>(subject: string, payload: unknown) => Promise<T>;

export function makeCallElixir(nc: NatsConnection): CallElixir {
  const enc = new TextEncoder();
  const dec = new TextDecoder();

  return async function callElixir<T>(subject: string, payload: unknown): Promise<T> {
    const msg = await nc.request(
      subject,
      enc.encode(JSON.stringify({ request_id: crypto.randomUUID(), payload })),
      { timeout: 5000 }
    );

    const response = JSON.parse(dec.decode(msg.data)) as {
      ok: boolean;
      data?: T;
      error?: string;
    };

    if (!response.ok) throw new Error(response.error || "Unknown error");
    return response.data!;
  };
}

// ─── Route factory ───────────────────────────────────────────────────────────

export type ParamExtractor = (c: Context<AppEnv>) => unknown | Promise<unknown>;

export interface ElixirHandlerOptions {
  /** HTTP status code on success (default: 200) */
  status?: number;
  /** HTTP status code on error (default: 400) */
  errorStatus?: number;
}

/**
 * Creates a Hono route handler that calls Elixir over NATS and returns JSON.
 *
 * @param subject   NATS subject, e.g. "db.note.create"
 * @param extractor Function that builds the payload from the Hono context
 * @param opts      Optional status code overrides
 */
export function makeCreateElixirHandler(callElixir: CallElixir) {
  return function createElixirHandler(
    subject: string,
    extractor: ParamExtractor,
    opts: ElixirHandlerOptions = {}
  ) {
    const { status = 200, errorStatus = 400 } = opts;

    return async (c: Context<AppEnv>) => {
      try {
        const payload = await extractor(c);
        const result = await callElixir(subject, payload);
        // 204 No Content — body must be empty
        if (status === 204) return c.body(null, 204);
        return c.json(result, status as 200 | 201);
      } catch (err) {
        return c.json({ error: (err as Error).message }, errorStatus as 400 | 401 | 404);
      }
    };
  };
}

// ─── Convenience bundle ──────────────────────────────────────────────────────

export function makeNats(nc: NatsConnection) {
  const callElixir = makeCallElixir(nc);
  const createElixirHandler = makeCreateElixirHandler(callElixir);
  return { callElixir, createElixirHandler };
}
