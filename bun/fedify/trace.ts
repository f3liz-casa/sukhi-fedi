// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Structured logger for the Bun service. Phase 1: emit JSON lines
// with a fixed field set so log aggregation can grep by field.
// Phase 2 will wire correlation_id through NATS headers.

export type Trace = {
  correlationId: string;
  rootActivityId?: string;
};

export function newTrace(): Trace {
  return { correlationId: crypto.randomUUID() };
}

export type LogLevel = "debug" | "info" | "warn" | "error";

export function logJson(
  trace: Trace | undefined,
  level: LogLevel,
  event: string,
  extra?: Record<string, unknown>,
): void {
  const line: Record<string, unknown> = {
    ts: new Date().toISOString(),
    level,
    service: "bun",
    event,
    correlation_id: trace?.correlationId,
    ...(extra ?? {}),
  };
  const s = JSON.stringify(line);
  if (level === "error" || level === "warn") console.error(s);
  else console.log(s);
}
