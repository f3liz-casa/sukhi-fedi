# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Release do
  @moduledoc """
  Release task stub. The gateway release owns all database migrations
  (including the shared `outbox`, `delivery_receipts`, and `oban_jobs`
  tables). Delivery's entrypoint therefore does not invoke this.

  Reintroduce a body here the first time delivery ships its own table.
  """

  @app :sukhi_delivery

  def migrate_all do
    load_app()
    :ok
  end

  defp load_app, do: Application.load(@app)
end
