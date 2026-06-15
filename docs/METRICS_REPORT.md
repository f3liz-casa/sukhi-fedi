# Metrics report — the Julia ↔ Elixir contract

The anomaly-detection pipeline has three stages:

```
sukhi-fedi (Elixir)          analysis/ (Julia)              sukhi-fedi (Elixir)
  metric_samples       →   pull /api/metrics, analyse   →    load report,
  (host-resource           write a small JSON report         flag live readings,
   time series)            (models + forecast)               warn on capacity
        ①                          ②  (this file)                   ③
```

Stage ① ships (`SukhiFedi.Metrics`, `GET /api/metrics`). Stage ② is
`analysis/metrics_report.jl`. Stage ③ reads the report this file
describes; until it lands, the report is still useful to read by eye.

The report is a **contract**: keep the shape stable, and bump the `schema`
string (`sukhi-fedi/metrics-report@2`) when it changes. Stage ② carries
the exact stage-③ checks in `analysis/test/runtests.jl` (`flagged/3`,
`maha_distance/2`) so the two never drift.

## Shape

```jsonc
{
  "schema": "sukhi-fedi/metrics-report@2",
  "generated_at": "2026-06-15T04:29:04Z",
  "params": { "k": 6.0, "min_samples": 48, "ewma_alpha": 0.05 },
  "window": { "samples": 4321, "since": "...Z", "until": "...Z" },

  "metrics": {
    "cpu_percent": {
      // value ≈ intercept + slope_per_day·days + Σ harmonics,
      // where days = (t − t0_unix)/86400 and, per harmonic at hours =
      // (t − t0_unix)/3600:  sin·sin(2π·k·hours/period_h) + cos·cos(…)
      "model": {
        "t0_unix": 1778905744, "intercept": 24.81, "slope_per_day": 0.011,
        "harmonics": [
          { "period_h": 24.0, "k": 1, "sin":  3.1, "cos": -8.4 },
          { "period_h": 24.0, "k": 2, "sin": -0.7, "cos":  1.2 },
          { "period_h": 24.0, "k": 3, "sin":  0.3, "cos": -0.4 }
        ]
      },
      // robust spread of the residual (value − model)
      "residual": { "median": -0.02, "madn": 3.98, "lower": -23.9, "upper": 23.8 },
      "ewma_alpha": 0.05
    }
    // ... one block per numeric signal. A metric with no rhythm (disk)
    //     has an empty "harmonics" and is a pure trend.
  },

  // joint check over the standardised residuals of several metrics
  "multivariate": {
    "columns":   ["cpu_percent", "load5", "mem_used", "disk_used_percent"],
    "scales":    [3.98, 0.13, 6.2e6, 0.51],          // per-column residual scale
    "mean":      [0.0, 0.0, 0.0, 0.0],               // ≈0 (residuals)
    "precision": [[...],[...],[...],[...]],           // inverse covariance (standardised)
    "threshold": 5.53                                 // flag sqrt(d²) above this
  },

  "forecast": {
    "mem_used": {
      "slope_per_day": 9.45e6, "current": 4.7e8, "ceiling": 805306368,
      "days_until_full": 35.3, "days_until_full_lo": 35.1, "days_until_full_hi": 35.4,
      "regime_since_unix": 1781000000,   // trend fit on data after the last change point
      "n_changepoints": 1
    },
    "disk_used_percent": { "slope_per_day": 0.80, "current": 63.7, "ceiling": 100.0,
                           "days_until_full": 45.3, "days_until_full_lo": 45.2,
                           "days_until_full_hi": 45.4, "regime_since_unix": ..., "n_changepoints": 0 }
  }
}
```

### Why a trend + harmonic model

A flat threshold lies about two things. Growing metrics (memory, disk)
read their own month-long climb as "spread" and set bounds so wide nothing
trips. Cyclic metrics (CPU follows a daily rhythm, often a weekly one too)
average the quiet night and the busy evening into one band that both
over-warns at 04:00 and under-warns at 21:00.

So each metric is **trend + harmonics + residual**:

- the **trend** (a line) removes monotone drift; its slope drives the
  capacity forecast, and removing it means a memory *spike* shows up apart
  from steady *growth*.
- the **harmonics** are a few sin/cos terms at periods an FFT-style
  periodogram actually found in the data (daily, weekly, …) — smoother and
  far fewer parameters than 24 hourly buckets, so the residual is tighter
  (on synthetic data, MADN 3.2 vs 5.7). A Hann window and neighbour/
  harmonic suppression keep spectral leakage from inventing fake periods.
- the **residual** is what's left. `madn` (median abs deviation × 1.4826)
  is a robust σ — it ignores the very spikes we want to catch, so the
  bounds aren't dragged out by them. A flat residual has `madn == 0` and
  `null` bounds (nothing to threshold against).

## Stage ③ live checks

### 1. Per-metric (point anomaly)

```
b         = report.metrics[m]
hours     = (unix(t) − b.model.t0_unix) / 3600
predicted = b.model.intercept + b.model.slope_per_day·(hours/24)
            + Σ over b.model.harmonics:  sin·sin(2π·k·hours/period_h) + cos·cos(…)
resid     = v − predicted
anomaly   = b.residual.lower != null && (resid < b.residual.lower || resid > b.residual.upper)
```

`k` (default 6) is the bound width in MADNs — higher = fewer, more
confident flags.

### 2. EWMA (sustained drift, online & adaptive)

The point check catches a single spike but not a slow shift that stays
*inside* the band yet sits persistently off-centre (a creeping regression
between report refreshes). Keep an exponentially-weighted mean of the
residual per metric, `α = ewma_alpha`:

```
m ← α·resid + (1−α)·m        (start m = 0)
drift = |m|                  # flag when drift > k·b.residual.madn
```

Cheap (one float of state per metric), and it adapts without re-fetching
the report. Transient spike → check 1; sustained drift → this.

### 3. Multivariate (correlation-breaking anomaly)

Catches a combination that's individually normal but jointly strange —
memory up while CPU is flat. Build the residual vector over
`multivariate.columns`, standardise, then the Mahalanobis quadratic:

```
for each column j:  zⱼ = (vⱼ − predictedⱼ) / scales[j]
d² = (z − mean)ᵀ · precision · (z − mean)
anomaly = sqrt(d²) > threshold
```

`precision` is row-major (`precision[i][j]`). It's a small dense matrix
(≤5×5), so this is a handful of multiplies per sample.

## Capacity

`forecast[r].days_until_full` is the headline, with `_lo`/`_hi` a band from
the slope's uncertainty — report it as a range, not false precision.
`null` means flat or shrinking (no ETA). The trend is fit on the **latest
regime only**: CUSUM finds the last change point (a leak starting, a
deploy), and `regime_since_unix` / `n_changepoints` say so — an old gentle
slope never dilutes a new steep one. Warn when `days_until_full_lo` drops
under, say, 14 days.
