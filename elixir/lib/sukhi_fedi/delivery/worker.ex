# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Delivery.Worker do
  @moduledoc """
  Oban worker that HTTP POSTs a signed Activity JSON-LD to a remote inbox.
  """

  use Oban.Worker, queue: :delivery, max_attempts: 10

  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Object

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"object_id" => object_id, "inbox_url" => inbox_url}}) do
    object = Repo.get!(Object, object_id)
    body = Jason.encode!(object.raw_json)

    case Req.post(inbox_url,
           body: body,
           headers: [{"content-type", "application/activity+json"}]
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status}} ->
        {:error, "unexpected status #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end
end
