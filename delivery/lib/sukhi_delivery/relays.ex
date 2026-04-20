# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Relays do
  @moduledoc """
  Minimal read-side helper: list inbox URLs of accepted relays. Mirror of
  the gateway's `SukhiFedi.Relays.get_active_inbox_urls/0`; the rest of
  relay CRUD lives on the gateway.
  """

  import Ecto.Query
  alias SukhiDelivery.Repo
  alias SukhiDelivery.Schema.Relay

  @doc "Return inbox URLs of all accepted relays."
  def get_active_inbox_urls do
    from(r in Relay, where: r.state == "accepted", select: r.inbox_uri)
    |> Repo.all()
  end
end
