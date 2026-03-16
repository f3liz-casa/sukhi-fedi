# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Delivery.FanOut do
  @moduledoc """
  Resolves recipient inboxes and enqueues Oban delivery jobs.
  """

  alias SukhiFedi.Delivery.Worker
  alias SukhiFedi.Schema.Object

  @doc """
  Enqueues one delivery job per inbox URL for the given object.
  """
  @spec enqueue(Object.t(), [String.t()]) :: :ok
  def enqueue(%Object{} = object, inbox_urls) when is_list(inbox_urls) do
    Enum.each(inbox_urls, fn inbox_url ->
      %{object_id: object.id, inbox_url: inbox_url}
      |> Worker.new()
      |> Oban.insert!()
    end)
  end
end
