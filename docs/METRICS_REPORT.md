# Metrics report — the Julia ↔ Elixir contract

The anomaly-detection pipeline has three stages:

```
sukhi-fedi (Elixir)          analysis/ (Julia)              sukhi-fedi (Elixir)
  metric_samples       →   pull /api/metrics, analyse   →    load report,
  (host-resource           write a small JSON report         flag live readings,
   time series)            (baselines + forecast)            warn on capacity
        ①                          ②  (this file)                   ③
```

Stage ① ships (`SukhiFedi.Metrics`, `GET /api/metrics`). Stage ② is
`analysis/metrics_report.jl`. Stage ③ reads the report this file
describes; until it lands, the report is still useful to read by eye.

The report is a **contract**: keep the shape stable, and bump the
`schema` string (`sukhi-fedi/metrics-report@1`) when it changes.

## Shape

```jsonc
{
  "schema": "sukhi-fedi/metrics-report@1",
  "generated_at": "2026-06-15T04:29:04Z",
  "params": { "k": 6.0, "min_samples": 48 },
  "window": { "samples": 4321, "since": "...Z", "until": "...Z" },

  "metrics": {
    "cpu_percent": {
      // value ≈ intercept + slope_per_day · (t − t0_unix)/86400
      "trend": { "t0_unix": 1778905744, "slope_per_day": 0.046, "intercept": 24.28 },
      // spread of the residual (value − trend), global fallback
      "residual": { "median": -0.16, "madn": 17.97, "lower": -108.0, "upper": 107.7 },
      // same, sliced by UTC hour — present only with enough data
      "seasonal_hour": {
        "4":  { "median": -7.37, "madn": 3.95, "lower": -31.07, "upper": 16.34 },
        "21": { "median": 17.65, "madn": 3.90, "lower":  -5.78, "upper": 41.07 }
      }
    }
    // ... one block per numeric signal
  },

  "forecast": {
    "mem_used":          { "slope_per_day": 9.45e6, "current": 4.7e8, "ceiling": 805306368, "days_until_full": 35.3 },
    "disk_used_percent": { "slope_per_day": 0.80,   "current": 63.7,  "ceiling": 100.0,     "days_until_full": 45.3 }
  }
}
```

### Why trend + residual, not a plain mean/threshold

A flat threshold lies about two things. Growing metrics (memory, disk)
would read their own month-long climb as "spread" and set bounds so wide
nothing ever trips. And cyclic metrics (CPU follows a daily rhythm) would
average the quiet night and the busy evening into one middling band that
both over-warns at 04:00 and under-warns at 21:00.

So each metric is modelled as **trend + residual**:

- `trend` removes monotone drift. Its slope feeds the capacity forecast;
  removing it means a memory *spike* is visible separately from steady
  *growth*.
- `residual` is what's left. `madn` (median absolute deviation × 1.4826)
  is a robust σ — it ignores the very spikes we want to catch, so the
  bounds don't get dragged out by them.
- `seasonal_hour` carries the daily cycle the straight line can't, as the
  residual spread per UTC hour. Prefer it when the hour is present.

A flat metric has `madn == 0`; its `lower`/`upper` are `null` (no bound).

## How stage ③ checks a live reading

For a reading `v` of metric `m` at time `t`:

```
b        = report.metrics[m]
days     = (unix(t) − b.trend.t0_unix) / 86400
predicted= b.trend.intercept + b.trend.slope_per_day · days
resid    = v − predicted
bounds   = b.seasonal_hour[hour_utc(t)]  (if present)  else  b.residual
anomaly  = bounds.lower != null && (resid < bounds.lower || resid > bounds.upper)
```

`k` (default 6) sets the width in MADNs — higher = fewer, more confident
flags. `analysis/test/runtests.jl` has this exact check in `flagged/3`.

For capacity: `forecast[r].days_until_full` is the headline. `null` means
flat or shrinking (no ETA). Warn under, say, 14 days.
