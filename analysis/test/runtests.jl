# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Run: julia --project=analysis analysis/test/runtests.jl
#
# No network: builds a synthetic series in memory, round-trips it through
# JSON (so the parse path is exercised too), and checks the report says
# what the data means — including the live checks (harmonic prediction,
# Mahalanobis) that stage ③ in Elixir will run.

using Test, Dates, Random, Statistics
import JSON3

include(joinpath(@__DIR__, "..", "metrics_report.jl"))

# ── the live checks, mirrored so the test pins the contract ────────────────────

function flagged(block, t::DateTime, v::Float64)
    resid = v - predict_at(block["model"], datetime2unix(t))
    b = block["residual"]
    lo, hi = b["lower"], b["upper"]
    (lo === nothing || hi === nothing) ? false : (resid < lo || resid > hi)
end

# x is the raw residual vector (vⱼ − predictedⱼ) in metric units; standardise
# by the stored scales, then the Mahalanobis quadratic — exactly stage ③.
function maha_distance(mv, x::Vector{Float64})
    s = collect(Float64, mv["scales"])
    μ = collect(Float64, mv["mean"])
    P = reduce(vcat, [reshape(collect(Float64, row), 1, :) for row in mv["precision"]])
    d = (x ./ s) .- μ
    sqrt((d' * P * d))
end

# ── synthetic: 40 days @ 10-min. cpu daily+weekly, memory leak midway,
#    residuals share a "busyness" factor so the metrics co-vary. ─────────────────

function synth(; seed = 7)
    rng = MersenneTwister(seed)
    t0 = DateTime(2026, 5, 1, 0, 0, 0)
    rows = Dict{Symbol,Any}[]
    mem_total = 768 * 1024 * 1024
    for i in 0:(40*144)
        t = t0 + Minute(10 * i)
        days = i / 144
        hod = hour(t) + minute(t) / 60
        dow = dayofweek(t)
        g = randn(rng)                                   # shared busyness factor

        cpu = max(0.0, 25 + 18 * cos((hod - 21) / 24 * 2pi) +
                       6 * cos((dow - 2) / 7 * 2pi) + 4g + randn(rng))
        load5 = cpu / 30 + 0.05 * (4g + randn(rng))
        # memory: 5 MiB/day until day 20, then a 20 MiB/day "leak"
        growth = days < 20 ? 5 * days : 5 * 20 + 20 * (days - 20)
        mem_used = round(Int, (180 + growth) * 1024 * 1024 + 5 * 1024 * 1024 * (4g + randn(rng)))
        beam = round(Int, 120 * 1024 * 1024 + 1.0e6 * (4g + randn(rng)))
        disk = 40 + 0.8 * days

        push!(rows, Dict{Symbol,Any}(
            :sampled_at => string(t) * "Z",
            :cpu_percent => cpu,
            :load5 => load5,
            :mem_used => mem_used,
            :mem_total => mem_total,
            :beam_processes => beam,
            :disk_used_percent => disk,
        ))
    end
    JSON3.read(JSON3.write(Dict(:samples => rows))) |> rows_of
end

@testset "build_report v2" begin
    rows = synth()
    rep = build_report(rows; k = 6.0)

    @test rep["schema"] == SCHEMA
    @test rep["window"]["samples"] == 40 * 144 + 1

    @testset "harmonic model finds daily + weekly" begin
        ps = [h["period_h"] for h in rep["metrics"]["cpu_percent"]["model"]["harmonics"]]
        @test any(p -> abs(p - 24) < 2, ps)             # daily
        @test any(p -> abs(p - 168) < 12, ps)           # weekly
        @test rep["metrics"]["cpu_percent"]["residual"]["madn"] < 6
    end

    @testset "flat metric: trend only, no harmonics" begin
        @test isempty(rep["metrics"]["disk_used_percent"]["model"]["harmonics"])
    end

    @testset "capacity forecast is regime-aware" begin
        f = rep["forecast"]["mem_used"]
        @test f["n_changepoints"] >= 1                  # the leak is found
        @test f["regime_since_unix"] > datetime2unix(parse_ts(rows[1].sampled_at))
        # forecast reflects the *latest* (steeper) slope, ~20 MiB/day
        @test f["slope_per_day"] > 12 * 1024 * 1024
        @test f["days_until_full"] !== nothing && f["days_until_full"] > 0
        @test f["days_until_full_lo"] <= f["days_until_full"]
        @test f["days_until_full_hi"] === nothing || f["days_until_full_hi"] >= f["days_until_full"]
    end

    @testset "live check: spike flagged, normal reading isn't" begin
        cpu = rep["metrics"]["cpu_percent"]
        t = DateTime(2026, 5, 30, 21, 0, 0)             # a busy hour
        pred = predict_at(cpu["model"], datetime2unix(t))
        @test flagged(cpu, t, pred + 60.0)              # a spike well above
        @test !flagged(cpu, t, pred + 2.0)              # ordinary jitter
    end

    @testset "multivariate catches a correlation-breaking point" begin
        mv = rep["multivariate"]
        cols = Symbol.(mv["columns"])
        @test length(cols) >= 3

        t = DateTime(2026, 5, 20, 12, 0, 0)
        # residual vector: cpu up, mem down — each modest on its own, but
        # the two normally rise together, so jointly it's strange.
        offs = Dict(:cpu_percent => +2.0 * rep["metrics"]["cpu_percent"]["residual"]["madn"],
                    :mem_used => -2.0 * rep["metrics"]["mem_used"]["residual"]["madn"])
        x = [get(offs, c, 0.0) for c in cols]           # residual = offset (others 0)

        # neither metric is flagged univariately …
        @test !flagged(rep["metrics"]["cpu_percent"], t,
                       predict_at(rep["metrics"]["cpu_percent"]["model"], datetime2unix(t)) + offs[:cpu_percent])
        @test !flagged(rep["metrics"]["mem_used"], t,
                       predict_at(rep["metrics"]["mem_used"]["model"], datetime2unix(t)) + offs[:mem_used])
        # … but the joint Mahalanobis distance clears the threshold.
        @test maha_distance(mv, x) > mv["threshold"]
    end
end

@testset "degenerate input" begin
    # Flat metric → MADN 0 → no bounds → never flags.
    rows = JSON3.read(JSON3.write(Dict(:samples => [
        Dict(:sampled_at => "2026-06-01T00:00:00Z", :cpu_percent => 10.0),
        Dict(:sampled_at => "2026-06-01T00:10:00Z", :cpu_percent => 10.0),
        Dict(:sampled_at => "2026-06-01T00:20:00Z", :cpu_percent => 10.0),
    ]))) |> rows_of
    rep = build_report(rows)
    b = rep["metrics"]["cpu_percent"]["residual"]
    @test b["madn"] == 0
    @test b["lower"] === nothing
    @test !haskey(rep, "multivariate")                  # too few columns/rows

    # Empty input → empty metrics, no crash.
    empty = build_report(rows_of(JSON3.read("{\"samples\": []}")))
    @test empty["window"]["samples"] == 0
    @test isempty(empty["metrics"])
end
