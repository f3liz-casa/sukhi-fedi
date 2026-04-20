# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.PromEx do
  use PromEx, otp_app: :sukhi_delivery

  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Ecto, otp_app: :sukhi_delivery, repos: [SukhiDelivery.Repo]},
      {PromEx.Plugins.Oban, queue_poll_rate: 5_000}
    ]
  end
end
