# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Config do
  @moduledoc false

  @spec domain!() :: String.t()
  def domain!, do: Application.fetch_env!(:sukhi_fedi, :domain)
end
