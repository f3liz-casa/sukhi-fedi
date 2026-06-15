# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Offline analysis of sukhi-fedi's host-resource history.
#
# Pulls the metric_samples time series from GET /api/metrics (or reads it
# from a file), then writes a small JSON *report* that the Elixir side
# loads to do live anomaly detection and capacity warnings. The report is
# the contract between this script and SukhiFedi — keep its shape stable
# (bump the `schema` string on a breaking change) and read
# docs/METRICS_REPORT.md, which carries the exact live-check formulas.
#
# Per numeric metric the report carries:
#   * a trend + harmonic model — a straight line for drift plus a few
#     sin/cos terms at periods discovered by an FFT-style periodogram
#     (daily, weekly, …). Fewer, smoother parameters than per-hour
#     buckets, and a tighter residual to threshold against.
#   * the robust spread (median + MADN → bounds) of that residual.
# Plus, across metrics:
#   * a multivariate block (mean + precision matrix over the residuals),
#     so a combination that breaks the usual correlation — memory up while
#     CPU is flat — is caught even when each metric alone looks normal.
#   * capacity forecasts that are regime-aware: CUSUM finds the latest
#     change point (a leak starting, a deploy) and the trend is fit only
#     on data after it, with a days-until-full *band*, not a false-precise
#     point.
#
# The cost split: this script does the expensive structure-finding offline
# (cheap at our scale — a row a minute is ~43k/month), and ships small
# coefficients so the live Elixir checks stay O(1) per sample.
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

using Statistics, StatsBase, Dates, Printf, LinearAlgebra
import JSON3, HTTP

const SCHEMA = "sukhi-fedi/metrics-report@2"
const MADN_CONST = 1.4826

# The numeric columns worth a model. sampled_at is the time axis; the byte
# totals (mem_total, disk_total) are ceilings, not signals.
const SIGNALS = [
    :cpu_percent, :load1, :load5, :load15,
    :mem_used, :mem_available, :swap_free,
    :beam_total, :beam_processes, :beam_binary,
    :disk_used_percent,
]

# Columns the multivariate block watches together. Curated to stay
# informative without near-duplicates (mem_available is ~ −mem_used; the
# three load averages move together) that would make the covariance
# singular. Degenerate (flat) columns are dropped at runtime too.
const MV_CANDIDATES = [:cpu_percent, :load5, :mem_used, :disk_used_percent, :beam_processes]

# Don't trust a model/forecast built from too little data.
const MIN_SAMPLES = 48
# Online adaptive smoothing constant Elixir uses on the residual stream
# (see the contract doc). ~0.05 ≈ a 20-sample memory.
const EWMA_ALPHA = 0.05

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

# ── robust spread ──────────────────────────────────────────────────────────────

robust(x) = (m = median(x); (median = m, madn = MADN_CONST * median(abs.(x .- m))))

"Bounds median ± k·MADN. A flat residual (MADN 0) gets no bounds — nothing
to threshold against, so leave it to whoever reads the series."
bounds(m, madn, k) = madn == 0 ? (nothing, nothing) : (m - k * madn, m + k * madn)

function resid_block(resid, k)
    r = robust(resid)
    lo, hi = bounds(r.median, r.madn, k)
    Dict{String,Any}("median" => r.median, "madn" => r.madn, "lower" => lo, "upper" => hi)
end

# ── time helpers ───────────────────────────────────────────────────────────────

unix(t::DateTime) = datetime2unix(t)
hours_since(times, t0) = [(unix(t) - t0) / 3600 for t in times]

"Average to one point per clock hour — enough resolution for period
discovery and change points, and far cheaper than per-minute."
function hourly(times, values)
    t0 = unix(times[1])
    buckets = Dict{Int,Vector{Float64}}()
    for (t, v) in zip(times, values)
        push!(get!(buckets, Int(div(unix(t) - t0, 3600)), Float64[]), v)
    end
    hs = sort(collect(keys(buckets)))
    Float64.(hs), [mean(buckets[h]) for h in hs]
end

# ── frequency: period discovery ────────────────────────────────────────────────

"Least-squares slope of y over x. nothing if it can't be fit."
function fit_slope(x, y)
    length(y) < 2 && return nothing
    x̄ = mean(x)
    sxx = sum((x .- x̄) .^ 2)
    sxx == 0 && return nothing
    sum((x .- x̄) .* (y .- mean(y))) / sxx
end

"""
Dominant *fundamental* periods (in hours), via a direct DFT power spectrum
over a grid of candidate periods. Three guards keep it honest:

  * a Hann window before the transform, so a period that isn't a whole
    number of cycles in the window doesn't smear into sidelobe ghosts
    (raw, 24h leaks fake peaks at ~21.5h and ~26.5h);
  * a robust floor (median + 8·MADN of the spectrum) — a metric with no
    rhythm (disk) clears nothing and is modelled by its trend alone;
  * neighbour/harmonic suppression — once 24h is taken, a peak within
    ±25% of it, or at a 2–4× ratio (its harmonics/subharmonics, which the
    model already covers via the k terms), is skipped.

Runs on the hourly-averaged series — cheap, and load lives at hour scale.
"""
function discover_periods(times, values; max_periods = 3, pmin = 3.0, pmax = 24.0 * 10)
    hs, xs = hourly(times, values)
    n = length(xs)
    n < 2pmin && return Float64[]
    # detrend so the zero-frequency ramp doesn't drown the peaks
    sl = fit_slope(hs, xs)
    xd = sl === nothing ? xs .- mean(xs) : xs .- (mean(xs) .+ sl .* (hs .- mean(hs)))
    # a (near-)flat metric has nothing periodic to find — bail before the
    # robust floor, computed on a dust spectrum, lets float noise through.
    # Relative to the level, so it fires on a clean linear ramp (disk) but
    # not on a real oscillation.
    MADN_CONST * median(abs.(xd .- median(xd))) < 1e-4 * (abs(median(xs)) + 1) &&
        return Float64[]
    w = 0.5 .* (1 .- cos.(2pi .* (0:n-1) ./ (n - 1)))     # Hann window
    xw = xd .* w
    grid = pmin:0.25:min(pmax, (hs[end] - hs[1]) / 2)
    isempty(grid) && return Float64[]
    pw = [abs(sum(xw .* cis.(-2pi * (1 / P) .* hs)))^2 for P in grid]
    # no peak stands out from the floor → call it noise, not a rhythm.
    (maximum(pw) <= 0 || maximum(pw) < 4 * mean(pw)) && return Float64[]
    thr = median(pw) + 8 * MADN_CONST * median(abs.(pw .- median(pw)))

    peaks = Float64[]
    for i in sortperm(pw, rev = true)
        pw[i] < thr && break
        P = grid[i]
        clashes = false
        for q in peaks
            if abs(P - q) < 0.25 * min(P, q)
                clashes = true; break
            end
            ratio = max(P, q) / min(P, q)
            if round(ratio) in 2:4 && abs(ratio - round(ratio)) < 0.08
                clashes = true; break
            end
        end
        clashes && continue
        push!(peaks, P)
        length(peaks) >= max_periods && break
    end
    peaks
end

# ── trend + harmonic model ─────────────────────────────────────────────────────

"""
Fit value ≈ intercept + slope·days + Σ harmonics, where each harmonic is
sinₖ·sin(2πk·hours/P) + cosₖ·cos(2πk·hours/P) at a discovered period P
(k = 1..3 for the strongest period, 1..2 for the rest). days and hours are
both measured from t0 (unix seconds). Returns the model and the residual.
"""
function fit_model(times, values)
    t0 = unix(times[1])
    hrs = hours_since(times, t0)
    days = hrs ./ 24
    periods = length(values) >= MIN_SAMPLES ? discover_periods(times, values) : Float64[]

    cols = Any[ones(length(values)), days]
    spec = Tuple{Float64,Int}[]
    for (i, P) in enumerate(periods), k in 1:(i == 1 ? 3 : 2)
        push!(cols, sin.(2pi * k .* hrs ./ P)); push!(cols, cos.(2pi * k .* hrs ./ P))
        push!(spec, (P, k))
    end
    A = reduce(hcat, cols)
    c = A \ values
    resid = values .- A * c

    harmonics = Dict{String,Any}[]
    for (j, (P, k)) in enumerate(spec)
        push!(harmonics, Dict{String,Any}(
            "period_h" => P, "k" => k, "sin" => c[2 + 2j - 1], "cos" => c[2 + 2j],
        ))
    end
    model = Dict{String,Any}(
        "t0_unix" => t0,
        "intercept" => c[1],
        "slope_per_day" => c[2],
        "harmonics" => harmonics,
    )
    model, resid
end

"Evaluate a fitted model at a unix time — the same arithmetic Elixir runs."
function predict_at(model, t_unix)
    hrs = (t_unix - model["t0_unix"]) / 3600
    v = model["intercept"] + model["slope_per_day"] * (hrs / 24)
    for h in model["harmonics"]
        ang = 2pi * h["k"] * hrs / h["period_h"]
        v += h["sin"] * sin(ang) + h["cos"] * cos(ang)
    end
    v
end

# ── change points + capacity forecast ──────────────────────────────────────────

"""
Change points in a series, by recursive CUSUM on the residual of a local
linear fit. A shift in the growth *rate* (a leak starting, a deploy
bumping the baseline) makes one straight line under- then over-shoot, so
the residual swings and Σ(rᵢ − mean r) builds a clear peak at the break —
which a per-step increment, swamped by noise, can't see. Heuristic
significance: the CUSUM range must beat a multiple of the residual noise.
Returns the unix times of the splits, oldest first. Runs on the hourly
series.
"""
function change_points(times, values; min_seg = 24, jump = 4.0)
    hs, xs = hourly(times, values)
    t0 = unix(times[1])
    cps = Int[]
    function seg(lo, hi)
        hi - lo < 2 * min_seg && return
        t = hs[lo:hi]; x = xs[lo:hi]
        sl = fit_slope(t, x)
        pred = sl === nothing ? fill(mean(x), length(x)) : mean(x) .+ sl .* (t .- mean(t))
        r = x .- pred
        S = cumsum(r .- mean(r))
        scale = MADN_CONST * median(abs.(r .- median(r)))
        scale == 0 && return
        (maximum(S) - minimum(S)) < jump * scale * sqrt(length(r)) && return
        k = argmax(abs.(S))
        (k < min_seg || length(x) - k < min_seg) && return
        push!(cps, lo - 1 + k)
        seg(lo, lo - 1 + k); seg(lo - 1 + k, hi)
    end
    seg(1, length(xs))
    sort([round(Int, t0 + hs[i] * 3600) for i in cps])
end

"""
Capacity forecast toward `ceiling`, fit on the latest regime only (data
after the last change point) so an old, gentler slope doesn't dilute a
new, steeper one. days_until_full carries a band from the slope's standard
error; nothing where the resource is flat/shrinking or the band stays
non-positive.
"""
function forecast_block(times, values, ceiling, cps)
    regime_since = isempty(cps) ? unix(times[1]) : last(cps)
    mask = [unix(t) >= regime_since for t in times]
    rt, rv = count(mask) >= 3 ? (times[mask], values[mask]) : (times, values)
    isempty(cps) || count(mask) >= 3 || (regime_since = unix(times[1]))

    t0 = unix(rt[1])
    days = [(unix(t) - t0) / 86_400 for t in rt]
    slope = fit_slope(days, rv)
    current = rv[end]

    until(sl) = (sl === nothing || sl <= 0 || ceiling === nothing) ? nothing :
                (ceiling - current) / sl

    # slope uncertainty → a days-until-full range
    lo = hi = nothing
    if slope !== nothing && length(rv) >= 3
        d̄ = mean(days); sxx = sum((days .- d̄) .^ 2)
        if sxx > 0
            pred = mean(rv) .+ slope .* (days .- d̄)
            σ = sqrt(sum((rv .- pred) .^ 2) / max(length(rv) - 2, 1))
            se = σ / sqrt(sxx)
            lo = until(slope + 1.96se)   # steepest plausible → soonest
            hi = until(slope - 1.96se)   # gentlest plausible → latest (nothing if it flattens)
        end
    end

    Dict{String,Any}(
        "slope_per_day" => slope,
        "current" => current,
        "ceiling" => ceiling,
        "days_until_full" => until(slope),
        "days_until_full_lo" => lo,
        "days_until_full_hi" => hi,
        "regime_since_unix" => regime_since,
        "n_changepoints" => length(cps),
    )
end

# ── multivariate (Mahalanobis over residuals) ──────────────────────────────────

"""
A mean + precision (inverse covariance) over the *standardised residuals*
of the chosen columns, plus a robust distance threshold. Residuals so each
column is already trend/season-free and the covariance is about how the
metrics deviate *together*; standardised (each ÷ its own robust scale)
because the raw residuals span bytes to percents — leave them unscaled and
the covariance is hopelessly ill-conditioned and the inverse is numerical
noise. A small ridge keeps the inverse stable.

Elixir checks a live vector: zⱼ = (vⱼ − predictedⱼ)/scaleⱼ, then
d² = (z−μ)ᵀ·precision·(z−μ); flag when sqrt(d²) > threshold.
"""
function multivariate_block(rows, models, resid_scale, k)
    # Skip a (near-)constant column: its residual scale is dust relative to
    # its level, so standardising would blow tiny float wobble up into
    # phantom anomalies. Relative test, since columns span bytes to percents.
    cols = [c for c in MV_CANDIDATES if haskey(models, c) &&
            get(resid_scale, c, 0.0) > 1e-6 * (abs(models[c]["intercept"]) + 1)]
    length(cols) < 2 && return nothing

    R = Vector{Float64}[]
    for r in rows
        vals = [tofloat(get(r, c, nothing)) for c in cols]
        any(isnothing, vals) && continue
        t = unix(parse_ts(r.sampled_at))
        push!(R, [vals[j] - predict_at(models[cols[j]], t) for j in eachindex(cols)])
    end
    length(R) < length(cols) + 2 && return nothing

    M = permutedims(reduce(hcat, R))          # observations × columns
    scales = [max(MADN_CONST * median(abs.(M[:, j] .- median(M[:, j]))), eps())
              for j in 1:size(M, 2)]
    Z = M ./ scales'
    μ = vec(mean(Z, dims = 1))
    Σ = cov(Z)
    Σ += (1e-6 * mean(diag(Σ)) + eps()) * I    # ridge
    P = inv(Σ)

    dists = [sqrt(max((Z[i, :] .- μ)' * P * (Z[i, :] .- μ), 0.0)) for i in 1:size(Z, 1)]
    rb = robust(dists)
    threshold = rb.median + k * rb.madn

    Dict{String,Any}(
        "columns" => string.(cols),
        "scales" => scales,
        "mean" => μ,
        "precision" => [P[i, :] for i in 1:size(P, 1)],
        "threshold" => threshold,
    )
end

# ── report ─────────────────────────────────────────────────────────────────────

function build_report(rows; k = 6.0)
    n = length(rows)
    metrics = Dict{String,Any}()
    models = Dict{Symbol,Any}()
    resid_scale = Dict{Symbol,Float64}()
    series = Dict{Symbol,Any}()

    for sig in SIGNALS
        times, values = column(rows, sig)
        isempty(values) && continue
        model, resid = fit_model(times, values)
        models[sig] = model
        resid_scale[sig] = MADN_CONST * median(abs.(resid .- median(resid)))
        series[sig] = (times = times, values = values)
        metrics[string(sig)] = Dict{String,Any}(
            "model" => model,
            "residual" => resid_block(resid, k),
            "ewma_alpha" => EWMA_ALPHA,
        )
    end

    # Capacity forecasts: memory toward mem_total, disk percent toward 100.
    fc = Dict{String,Any}()
    if haskey(series, :mem_used)
        _, totals = column(rows, :mem_total)
        ceiling = isempty(totals) ? nothing : totals[end]
        s = series[:mem_used]
        fc["mem_used"] = forecast_block(s.times, s.values, ceiling, change_points(s.times, s.values))
    end
    if haskey(series, :disk_used_percent)
        s = series[:disk_used_percent]
        fc["disk_used_percent"] =
            forecast_block(s.times, s.values, 100.0, change_points(s.times, s.values))
    end

    mv = multivariate_block(rows, models, resid_scale, k)

    window = if n == 0
        Dict{String,Any}("samples" => 0)
    else
        ts = [parse_ts(r.sampled_at) for r in rows]
        Dict{String,Any}(
            "samples" => n,
            "since" => string(minimum(ts)) * "Z",
            "until" => string(maximum(ts)) * "Z",
        )
    end

    report = Dict{String,Any}(
        "schema" => SCHEMA,
        "generated_at" => string(now(UTC)) * "Z",
        "params" => Dict{String,Any}("k" => k, "min_samples" => MIN_SAMPLES, "ewma_alpha" => EWMA_ALPHA),
        "window" => window,
        "metrics" => metrics,
        "forecast" => fc,
    )
    mv === nothing || (report["multivariate"] = mv)
    report
end

# ── cli ────────────────────────────────────────────────────────────────────────

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
