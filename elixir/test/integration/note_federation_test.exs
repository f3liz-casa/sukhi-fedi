# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule SukhiFedi.Integration.NoteFederationTest do
  @moduledoc """
  Integration test scaffold. Real scenarios (local note post -> mock remote
  inbox delivery, failure -> Oban retry) are added in stage 1 onward.
  """

  use SukhiFedi.IntegrationCase, async: false

  @moduletag :integration

  describe "stage-0 smoke" do
    test "mock remote bypass is openable", %{mock_remote: bypass} do
      assert is_integer(bypass.port)
      assert bypass.port > 0
    end
  end
end
