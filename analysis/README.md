# analysis/ — offline metrics analysis (Julia)

Stage ② of the anomaly-detection pipeline. Pulls sukhi-fedi's
host-resource history (`GET /api/metrics`, stage ①) and writes a small
JSON report the Elixir side loads for live anomaly detection and capacity
warnings (stage ③). The report format — the contract between this and
sukhi-fedi — is [`../docs/METRICS_REPORT.md`](../docs/METRICS_REPORT.md).

## Setup

```sh
julia --project=analysis -e 'using Pkg; Pkg.instantiate()'
```

## Run

```sh
# Fetch the last 30 days from the server and print the report:
export METRICS_URL=https://your-host/api/metrics
export METRICS_TOKEN=...                       # same as the box's METRICS_TOKEN
julia --project=analysis analysis/metrics_report.jl --out report.json

# Analyse a saved dump instead of fetching (use - for stdin):
curl -H "Authorization: Bearer $METRICS_TOKEN" "$METRICS_URL?since=$(date -v-14d +%s)" \
  | julia --project=analysis analysis/metrics_report.jl --file -
```

Flags: `--days N` (history window when fetching, default 30), `--k X`
(bound width in MADNs, default 6), `--out PATH`, `--file PATH`.

## Test

```sh
julia --project=analysis analysis/test/runtests.jl
```

No network — it builds a synthetic month of samples and checks the report
says what the data means (flat CPU trend, captured daily rhythm, finite
days-until-full, a spike flagged by the same check stage ③ will run).

## What it computes

Per numeric metric: a linear **trend** (its slope drives the capacity
forecast), the robust **residual** spread around it (median + MADN →
bounds), and that spread sliced by **UTC hour** when there's enough data.
Plus a capacity **forecast** for memory (toward `mem_total`) and disk
(toward 100%): days until full. The *why* is in the contract doc.

> Note: until enough history accrues on the box, forecasts and seasonal
> slices will be thin or absent — that's expected. Let it run a couple of
> weeks before trusting the days-until-full numbers.
