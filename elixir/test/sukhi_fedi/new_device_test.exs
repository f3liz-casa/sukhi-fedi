# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.NewDeviceTest do
  @moduledoc """
  The pure new-device predicate behind the login heads-up
  (`LocalAccounts.new_device?/2`). No DB — it takes a fingerprint and
  the list of prior ones and answers a boolean.
  """

  use ExUnit.Case, async: true

  # Picked up by the `--only integration` runner alongside the DB suite.
  @moduletag :integration

  alias SukhiFedi.LocalAccounts

  test "an exact (ip, ua) match is a known device" do
    prior = [{"203.0.113.7", "Firefox"}, {"198.51.100.2", "Safari"}]
    refute LocalAccounts.new_device?({"203.0.113.7", "Firefox"}, prior)
  end

  test "a never-seen pair is a new device" do
    prior = [{"203.0.113.7", "Firefox"}]
    assert LocalAccounts.new_device?({"198.51.100.2", "Safari"}, prior)
  end

  test "same IP but a different UA is new (and vice versa)" do
    prior = [{"203.0.113.7", "Firefox"}]
    assert LocalAccounts.new_device?({"203.0.113.7", "Safari"}, prior)
    assert LocalAccounts.new_device?({"198.51.100.2", "Firefox"}, prior)
  end

  test "the first session ever (no priors) is a new device" do
    assert LocalAccounts.new_device?({"203.0.113.7", "Firefox"}, [])
  end

  test "a blank fingerprint (no IP, no UA) stays silent" do
    # Nothing to recognise a device by → don't cry "new device".
    refute LocalAccounts.new_device?({nil, nil}, [])
    refute LocalAccounts.new_device?({nil, nil}, [{"203.0.113.7", "Firefox"}])
  end

  test "matches a prior partial fingerprint (IP only) exactly" do
    prior = [{"203.0.113.7", nil}]
    refute LocalAccounts.new_device?({"203.0.113.7", nil}, prior)
    assert LocalAccounts.new_device?({"203.0.113.7", "Firefox"}, prior)
  end
end
