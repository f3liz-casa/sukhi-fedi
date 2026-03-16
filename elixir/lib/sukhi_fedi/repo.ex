# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Repo do
  use Ecto.Repo,
    otp_app: :sukhi_fedi,
    adapter: Ecto.Adapters.Postgres
end
