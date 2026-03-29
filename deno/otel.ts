// SPDX-License-Identifier: AGPL-3.0-or-later
//
// OpenTelemetry helpers for the Deno worker.
// Deno 2.x provides built-in OTEL support when started with --unstable-otel.
// Set OTEL_DENO=1 and the standard OTEL_* env vars to enable export.
//
// Docs: https://docs.deno.com/runtime/fundamentals/open_telemetry/

import { SpanStatusCode, trace } from "@opentelemetry/api";

export const tracer = trace.getTracer("sukhi-fedi-deno", "0.1.0");
export { SpanStatusCode };
