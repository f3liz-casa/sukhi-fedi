# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Delivery.WorkerKnockTest do
  # async: false — shares the :delivery_httpsig_spec ETS table with
  # SigSpec; runs under `mix test --no-start` (no DB/NATS needed because
  # knock_loop/3 takes a fake poster instead of doing real HTTP/signing).
  use ExUnit.Case, async: false

  alias SukhiDelivery.Delivery.{Worker, SigSpec}

  setup_all do
    if :ets.whereis(:delivery_httpsig_spec) == :undefined do
      :ets.new(:delivery_httpsig_spec, [:named_table, :public, read_concurrency: true])
    end

    :ok
  end

  defp uniq_host, do: "peer-#{System.unique_integer([:positive])}.example"

  # A poster that records which specs it was asked to sign with, and
  # replies from a spec→response map.
  defp recording_poster(responses) do
    test = self()

    fn spec ->
      send(test, {:posted, spec})
      Map.fetch!(responses, spec)
    end
  end

  test "accepts on the first spec, posts once, learns it" do
    host = uniq_host()
    poster = recording_poster(%{cavage: {:ok, %{status: 202}}})

    assert {:ok, %{status: 202}} = Worker.knock_loop(host, :cavage, poster)
    assert_received {:posted, :cavage}
    refute_received {:posted, :rfc9421}
    assert SigSpec.spec_for(host) == :cavage
  end

  test "knocks to the other spec on 401 and learns the one that worked" do
    host = uniq_host()
    poster = recording_poster(%{cavage: {:ok, %{status: 401}}, rfc9421: {:ok, %{status: 202}}})

    assert {:ok, %{status: 202}} = Worker.knock_loop(host, :cavage, poster)
    assert_received {:posted, :cavage}
    assert_received {:posted, :rfc9421}
    assert SigSpec.spec_for(host) == :rfc9421
  end

  test "both specs rejected → returns the first result and learns nothing" do
    host = uniq_host()
    poster = recording_poster(%{cavage: {:ok, %{status: 401}}, rfc9421: {:ok, %{status: 400}}})

    assert {:ok, %{status: 401}} = Worker.knock_loop(host, :cavage, poster)
    assert_received {:posted, :cavage}
    assert_received {:posted, :rfc9421}
    # nothing learned: spec_for falls back to the rfc9421 default, so the
    # next delivery probes again rather than locking onto a wrong spec.
    assert SigSpec.spec_for(host) == :rfc9421
  end

  test "a non-rejection status (404) is not a knock; spec learned, no retry" do
    host = uniq_host()
    poster = recording_poster(%{cavage: {:ok, %{status: 404}}})

    assert {:ok, %{status: 404}} = Worker.knock_loop(host, :cavage, poster)
    refute_received {:posted, :rfc9421}
    assert SigSpec.spec_for(host) == :cavage
  end

  test "a transport error is returned without knocking" do
    host = uniq_host()
    poster = recording_poster(%{cavage: {:error, :timeout}})

    assert {:error, :timeout} = Worker.knock_loop(host, :cavage, poster)
    refute_received {:posted, :rfc9421}
  end

  test "from the rfc9421 default, knocks back to cavage for a cavage-only peer" do
    host = uniq_host()
    poster = recording_poster(%{rfc9421: {:ok, %{status: 401}}, cavage: {:ok, %{status: 202}}})

    # spec_for defaults to rfc9421 — the worker tries it first, then
    # knocks to cavage for a peer that hasn't adopted RFC 9421 yet.
    assert SigSpec.spec_for(host) == :rfc9421
    assert {:ok, %{status: 202}} = Worker.knock_loop(host, SigSpec.spec_for(host), poster)
    assert_received {:posted, :rfc9421}
    assert_received {:posted, :cavage}
    assert SigSpec.spec_for(host) == :cavage
  end
end
