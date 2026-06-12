# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Delivery.SigSpecTest do
  # async: false — the learned-spec table is a shared named ETS table.
  use ExUnit.Case, async: false

  alias SukhiDelivery.Delivery.SigSpec

  # SigSpec only touches the :delivery_httpsig_spec ETS table, not the DB,
  # so these run under `mix test --no-start`: create the table the
  # Cache.Ets GenServer would normally own.
  setup_all do
    if :ets.whereis(:delivery_httpsig_spec) == :undefined do
      :ets.new(:delivery_httpsig_spec, [:named_table, :public, read_concurrency: true])
    end

    :ok
  end

  setup do
    on_exit(fn -> :ets.delete_all_objects(:delivery_httpsig_spec) end)
    :ok
  end

  test "an unknown host defaults to rfc9421 (the direction of migration)" do
    assert SigSpec.spec_for("unknown-#{System.unique_integer([:positive])}.example") == :rfc9421
  end

  test "a learned value wins over the rfc9421 default" do
    host = "peer-#{System.unique_integer([:positive])}.example"
    assert SigSpec.spec_for(host) == :rfc9421
    :ok = SigSpec.learn(host, :cavage)
    assert SigSpec.spec_for(host) == :cavage

    # A learned change is followed too (e.g. the peer added RFC 9421).
    :ok = SigSpec.learn(host, :rfc9421)
    assert SigSpec.spec_for(host) == :rfc9421
  end

  test "alt/1 flips the spec — what we re-sign with on a knock" do
    assert SigSpec.alt(:cavage) == :rfc9421
    assert SigSpec.alt(:rfc9421) == :cavage
  end

  test "knock? fires only on signature-rejection statuses" do
    assert SigSpec.knock?(401)
    assert SigSpec.knock?(400)

    # Success, block, gone, rate, server error: never a spec problem —
    # knocking there would double every POST.
    refute SigSpec.knock?(200)
    refute SigSpec.knock?(202)
    refute SigSpec.knock?(403)
    refute SigSpec.knock?(404)
    refute SigSpec.knock?(410)
    refute SigSpec.knock?(429)
    refute SigSpec.knock?(500)
  end

  test "a nil host defaults to rfc9421 and learn/2 is a harmless no-op" do
    assert SigSpec.spec_for(nil) == :rfc9421
    assert SigSpec.learn(nil, :rfc9421) == :ok
  end
end
