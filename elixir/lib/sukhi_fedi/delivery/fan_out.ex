# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Delivery.FanOut do
  @moduledoc """
  Resolves recipient inboxes and enqueues Oban delivery jobs.
  """

  alias SukhiFedi.Delivery.Worker
  alias SukhiFedi.Schema.Object
  alias SukhiFedi.Relays

  @doc """
  Enqueues one delivery job per inbox URL for the given object.
  Relay inboxes (accepted subscriptions) are automatically included.
  """
  @spec enqueue(Object.t(), [String.t()]) :: :ok
  def enqueue(%Object{} = object, inbox_urls) when is_list(inbox_urls) do
    relay_inboxes = Relays.get_active_inbox_urls()
    all_inboxes = Enum.uniq(inbox_urls ++ relay_inboxes)

    Enum.each(all_inboxes, fn inbox_url ->
      %{object_id: object.id, inbox_url: inbox_url}
      |> Worker.new()
      |> Oban.insert!()
    end)
  end
end
