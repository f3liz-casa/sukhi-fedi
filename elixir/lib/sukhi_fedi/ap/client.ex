# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.AP.Client do
  @moduledoc """
  NATS request/reply wrapper for communicating with Deno workers.
  """

  @timeout 5_000

  @doc """
  Sends a request to the given NATS topic and returns the reply.
  """
  @spec request(String.t(), map()) :: {:ok, term()} | {:error, String.t()}
  def request(topic, payload) do
    message = Jason.encode!(%{request_id: request_id(), payload: payload})

    case Gnat.request(:gnat, topic, message, receive_timeout: @timeout) do
      {:ok, %{body: body}} ->
        case Jason.decode!(body) do
          %{"ok" => true, "data" => data} -> {:ok, data}
          %{"ok" => false, "error" => error} -> {:error, error}
        end

      {:error, :timeout} ->
        {:error, "timeout"}
    end
  end

  defp request_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
