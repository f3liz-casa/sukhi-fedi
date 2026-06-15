# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Run: julia --project=analysis analysis/test/runtests.jl
#
# No network: builds a synthetic series in memory, round-trips it through
# JSON (so the parse path is exercised too), and checks the report says
# what the data means.

using Test, Dates, Random
import JSON3

include(joinpath(@__DIR__, "..", "metrics_report.jl"))

# Replicates the live anomaly check Elixir will do, so the test pins the
# contract: predicted from the trend, residual, prefer the hour's bounds.
function flagged(block, t::DateTime, v::Float64)
    tr = block["trend"]
    days = (datetime2unix(t) - tr["t0_unix"]) / 86_400
    resid = v - (tr["intercept"] + tr["slope_per_day"] * days)

    rb = get(block, "seasonal_hour", Dict())
    h = string(hour(t))
    b = haskey(rb, h) ? rb[h] : block["residual"]

    lo, hi = b["lower"], b["upper"]
    (lo === nothing || hi === nothing) ? false : (resid < lo || resid > hi)
end

# A month of 10-minute samples: daily cpu rhythm, steady memory growth.
function synth(; seed = 1)
    rng = MersenneTwister(seed)
    t0 = DateTime(2026, 5, 16, 0, 0, 0)
    rows = Dict{Symbol,Any}[]
    mem_total = 768 * 1024 * 1024
    for i in 0:(30*144)
        t = t0 + Minute(10 * i)
        hod = hour(t) + minute(t) / 60
        cpu = max(0.0, 25 + 18 * cos((hod - 21) / 24 * 2pi) + 3 * randn(rng))
        days = i / 144
        mem_used = round(Int, (180 + 9 * days) * 1024 * 1024 + 4 * 1024 * 1024 * randn(rng))
        push!(rows, Dict{Symbol,Any}(
            :sampled_at => string(t) * "Z",
            :cpu_percent => cpu,
            :load1 => cpu / 25,
            :mem_used => mem_used,
            :mem_total => mem_total,
            :disk_used_percent => 40 + 0.8 * days,
        ))
    end
    JSON3.read(JSON3.write(Dict(:samples => rows))) |> rows_of
end

@testset "build_report" begin
    rows = synth()
    rep = build_report(rows; k = 6.0)

    @test rep["schema"] == SCHEMA
    @test rep["window"]["samples"] == 30 * 144 + 1

    @testset "cpu: trend ~flat, seasonal rhythm captured" begin
        cpu = rep["metrics"]["cpu_percent"]
        @test abs(cpu["trend"]["slope_per_day"]) < 1.0          # no real drift
        @test haskey(cpu, "seasonal_hour")
        # busy hour sits well above the quiet hour
        @test cpu["seasonal_hour"]["21"]["median"] > cpu["seasonal_hour"]["4"]["median"] + 10
    end

    @testset "memory: growing trend, finite days-until-full" begin
        f = rep["forecast"]["mem_used"]
        @test f["slope_per_day"] > 0
        @test f["days_until_full"] !== nothing
        @test f["days_until_full"] > 0
    end

    @testset "disk forecast toward 100%" begin
        f = rep["forecast"]["disk_used_percent"]
        @test f["ceiling"] == 100.0
        @test f["days_until_full"] > 0
    end

    @testset "live check: spike flagged, normal reading isn't" begin
        cpu = rep["metrics"]["cpu_percent"]
        # 21:00 is busy (~42%); a normal busy reading must not flag, a
        # 98% spike must.
        t = DateTime(2026, 6, 16, 21, 0, 0)
        @test flagged(cpu, t, 98.0)
        @test !flagged(cpu, t, 42.0)
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

    # Empty input → empty metrics, no crash.
    empty = build_report(rows_of(JSON3.read("{\"samples\": []}")))
    @test empty["window"]["samples"] == 0
    @test isempty(empty["metrics"])
end
