# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Offline analysis of sukhi-fedi's host-resource history.
#
# Pulls the metric_samples time series from GET /api/metrics (or reads it
# from a file), then writes a small JSON *report* that the Elixir side
# loads to do live anomaly detection and capacity warnings. The report is
# the contract between this script and SukhiFedi — keep its shape stable
# (see schema string below), and read docs/METRICS_REPORT.md.
#
# What it computes, per numeric metric:
#   * robust baseline — median and MADN (1.4826 × median-abs-deviation,
#     which approximates σ for normal data but ignores the spikes we want
#     to catch), and bounds median ± k·MADN.
#   * a seasonal profile by UTC hour-of-day, when there's enough data —
#     server load has a daily rhythm, so 03:00 quiet and 21:00 busy
#     shouldn't share one threshold.
# And a capacity forecast for memory and disk: a linear trend over time
# → days until the resource reaches its ceiling.
#
# Usage:
#   julia --project=analysis analysis/metrics_report.jl            # fetch + print
#   julia --project=analysis analysis/metrics_report.jl --out report.json
#   julia --project=analysis analysis/metrics_report.jl --file rows.json
#   ... --file -        # read sample JSON from stdin
#   ... --days 14       # history window when fetching (default 30)
#   ... --k 5.0         # bound width in MADNs (default 6)
#
# Env (fetch mode): METRICS_URL (e.g. https://host/api/metrics), METRICS_TOKEN.

using Statistics, StatsBase, Dates, Printf
import JSON3, HTTP

const SCHEMA = "sukhi-fedi/metrics-report@1"
const MADN_CONST = 1.4826

# The numeric columns worth a baseline. sampled_at is the time axis; the
# byte totals (mem_total, disk_total) are ceilings, not signals.
const SIGNALS = [
    :cpu_percent, :load1, :load5, :load15,
    :mem_used, :mem_available, :swap_free,
    :beam_total, :beam_processes, :beam_binary,
    :disk_used_percent,
]

# Don't trust a seasonal/global baseline built from too little data.
const MIN_SAMPLES = 48
const MIN_PER_HOUR = 12

# ── loading ──────────────────────────────────────────────────────────────────

"Parse one ISO8601 string to a DateTime, dropping fractional seconds and Z."
parse_ts(s::AbstractString) = DateTime(first(s, 19))  # \"yyyy-mm-ddTHH:MM:SS\"

"Coerce a JSON value to Float64, or `nothing` for null/missing."
function tofloat(v)
    v === nothing && return nothing
    v isa Number ? Float64(v) : nothing
end

"Normalise input JSON (endpoint `{samples:[...]}` or a bare array) to rows."
function rows_of(json)
    if json isa JSON3.Object && haskey(json, :samples)
        return json.samples
    elseif json isa JSON3.Array
        return json
    else
        error("unexpected JSON shape: expected an array or {\"samples\": [...]}")
    end
end

function load_from_file(path)
    text = path == "-" ? read(stdin, String) : read(path, String)
    rows_of(JSON3.read(text))
end

function fetch_samples(url, token, days)
    isempty(url) && error("METRICS_URL is not set (and no --file given)")
    since = round(Int, datetime2unix(now(UTC))) - days * 86_400
    full = string(url, "?since=", since)
    headers = ["Authorization" => "Bearer " * token]
    resp = HTTP.get(full, headers; status_exception=true)
    rows_of(JSON3.read(resp.body))
end

# ── statistics ───────────────────────────────────────────────────────────────

"median + MADN over a non-empty vector."
function robust(x::Vector{Float64})
    m = median(x)
    madn = MADN_CONST * median(abs.(x .- m))
    (median = m, madn = madn)
end

"Bounds median ± k·MADN. A flat metric (MADN 0) gets no bounds — any
deviation there is real, but flagging on a hair-trigger isn't useful, so
we leave that judgement to whoever reads the series."
function bounds(median, madn, k)
    madn == 0 ? (nothing, nothing) : (median - k * madn, median + k * madn)
end

"A residual block: where the trend-removed value usually sits, and the
bounds a live reading is checked against."
function resid_block(resid::Vector{Float64}, k)
    r = robust(resid)
    lo, hi = bounds(r.median, r.madn, k)
    Dict{String,Any}("median" => r.median, "madn" => r.madn, "lower" => lo, "upper" => hi)
end

"Least-squares slope of y over t (days), or nothing if it can't be fit."
function fit_slope(tdays::Vector{Float64}, y::Vector{Float64})
    length(y) < 2 && return nothing
    t̄ = mean(tdays)
    sxx = sum((tdays .- t̄) .^ 2)
    sxx == 0 && return nothing
    sum((tdays .- t̄) .* (y .- mean(y))) / sxx
end

"Fit a line value ≈ intercept + slope·(days since t0). A series with no
fittable slope is treated as flat at its median. t0 is unix seconds so
Elixir can re-evaluate the prediction at any later instant."
function fit_trend(times::Vector{DateTime}, values::Vector{Float64})
    t0 = datetime2unix(times[1])
    tdays = [(datetime2unix(t) - t0) / 86_400 for t in times]
    slope = fit_slope(tdays, values)
    if slope === nothing
        (t0 = t0, slope = 0.0, intercept = median(values), tdays = tdays)
    else
        (t0 = t0, slope = slope, intercept = mean(values) - slope * mean(tdays), tdays = tdays)
    end
end

predict(tr, tdays) = tr.intercept .+ tr.slope .* tdays

"""
The full per-metric block: a linear trend, the spread of the residual
around it (so monotone growth doesn't masquerade as noise), and — when
there's enough data — that residual spread sliced by UTC hour, which is
what catches a daily rhythm the straight-line trend can't.

Elixir checks a live reading `v` at time `t` like this: predicted =
intercept + slope·(t − t0)/86400; resid = v − predicted; pick the hour's
bounds if present else the global ones; flag when resid falls outside.
"""
function metric_block(times::Vector{DateTime}, values::Vector{Float64}, k)
    tr = fit_trend(times, values)
    resid = values .- predict(tr, tr.tdays)

    block = Dict{String,Any}(
        "trend" => Dict{String,Any}(
            "t0_unix" => tr.t0,
            "slope_per_day" => tr.slope,
            "intercept" => tr.intercept,
        ),
        "residual" => resid_block(resid, k),
    )

    if length(values) >= MIN_SAMPLES
        season = Dict{String,Any}()
        for h in 0:23
            mask = hour.(times) .== h
            count(mask) >= MIN_PER_HOUR && (season[string(h)] = resid_block(resid[mask], k))
        end
        isempty(season) || (block["seasonal_hour"] = season)
    end

    block
end

"Capacity forecast from an already-fitted trend toward `ceiling`.
days_until_full is nothing when flat/shrinking or the ceiling is unknown."
function forecast_block(tr, current, ceiling)
    days = (tr.slope <= 0 || ceiling === nothing) ? nothing : (ceiling - current) / tr.slope
    Dict{String,Any}(
        "slope_per_day" => tr.slope,
        "current" => current,
        "ceiling" => ceiling,
        "days_until_full" => days,
    )
end

# ── report ───────────────────────────────────────────────────────────────────

"Pull metric `col` across rows as aligned (times, values), dropping rows
where the value is null."
function column(rows, col::Symbol)
    times = DateTime[]
    values = Float64[]
    for r in rows
        v = tofloat(get(r, col, nothing))
        v === nothing && continue
        push!(times, parse_ts(r.sampled_at))
        push!(values, v)
    end
    times, values
end

function build_report(rows; k = 6.0)
    n = length(rows)
    metrics = Dict{String,Any}()
    trends = Dict{Symbol,Any}()  # reused by the forecasts below
    for sig in SIGNALS
        times, values = column(rows, sig)
        isempty(values) && continue
        metrics[string(sig)] = metric_block(times, values, k)
        trends[sig] = (trend = fit_trend(times, values), current = values[end])
    end

    # Capacity forecasts reuse the metric's own trend: memory toward
    # mem_total, disk percent toward 100.
    fc = Dict{String,Any}()
    if haskey(trends, :mem_used)
        _, totals = column(rows, :mem_total)
        ceiling = isempty(totals) ? nothing : totals[end]
        fc["mem_used"] = forecast_block(trends[:mem_used].trend, trends[:mem_used].current, ceiling)
    end
    if haskey(trends, :disk_used_percent)
        fc["disk_used_percent"] =
            forecast_block(trends[:disk_used_percent].trend, trends[:disk_used_percent].current, 100.0)
    end

    window = if n == 0
        Dict("samples" => 0)
    else
        ts = [parse_ts(r.sampled_at) for r in rows]
        Dict(
            "samples" => n,
            "since" => string(minimum(ts)) * "Z",
            "until" => string(maximum(ts)) * "Z",
        )
    end

    Dict(
        "schema" => SCHEMA,
        "generated_at" => string(now(UTC)) * "Z",
        "params" => Dict("k" => k, "min_samples" => MIN_SAMPLES),
        "window" => window,
        "metrics" => metrics,
        "forecast" => fc,
    )
end

# ── cli ──────────────────────────────────────────────────────────────────────

function parse_args(argv)
    opts = Dict{String,Any}("file" => nothing, "out" => nothing, "days" => 30, "k" => 6.0)
    i = 1
    while i <= length(argv)
        a = argv[i]
        if a == "--file"
            opts["file"] = argv[i+1]; i += 2
        elseif a == "--out"
            opts["out"] = argv[i+1]; i += 2
        elseif a == "--days"
            opts["days"] = parse(Int, argv[i+1]); i += 2
        elseif a == "--k"
            opts["k"] = parse(Float64, argv[i+1]); i += 2
        else
            error("unknown argument: $a")
        end
    end
    opts
end

function main(argv)
    opts = parse_args(argv)

    rows = if opts["file"] !== nothing
        load_from_file(opts["file"])
    else
        fetch_samples(get(ENV, "METRICS_URL", ""), get(ENV, "METRICS_TOKEN", ""), opts["days"])
    end

    report = build_report(rows; k = opts["k"])
    json = JSON3.write(report)

    if opts["out"] === nothing
        println(json)
    else
        write(opts["out"], json)
        @printf(stderr, "wrote %s (%d samples)\n", opts["out"], length(rows))
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
