# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Repo do
  use Ecto.Repo,
    otp_app: :sukhi_delivery,
    adapter: Ecto.Adapters.Postgres
end
