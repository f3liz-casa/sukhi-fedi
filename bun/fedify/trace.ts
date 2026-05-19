// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Structured logger for the Bun service. One JSON line per call with
// a fixed field set so a log aggregator can grep by field. The
// correlation id is generated here when no upstream id is provided;
// callers that already have one (currently `handlers/inbox.ts`'s
// `payload.correlationId`) pass it through.

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
