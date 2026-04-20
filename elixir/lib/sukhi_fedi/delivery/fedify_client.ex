# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Delivery.FedifyClient do
  @moduledoc """
  NATS Micro client for the Deno `fedify` service.

  Wraps request/reply to the service endpoints:

    * `fedify.translate.v1` — build ActivityPub JSON-LD from a domain object
    * `fedify.sign.v1`      — sign an outbound HTTP request envelope
    * `fedify.verify.v1`    — verify an incoming signed HTTP request

  The service is queue-grouped (`fedify-workers`) on the Deno side so
  multiple replicas share load automatically.

  Coexists with the legacy `SukhiFedi.AP.Client` (subjects `ap.*`) during
  the stage-2/3 migration — callers are switched over piece by piece.
  """

  @timeout 10_000

  @doc """
  Build ActivityPub JSON-LD for the given object type.

  Supported `object_type` values: `"note"`, `"follow"`, `"accept"`,
  `"announce"`, `"actor"`, `"dm"`, `"add"`, `"remove"`, `"integrity_proof"`.
  """
  @spec translate(String.t(), map()) :: {:ok, term()} | {:error, term()}
  def translate(object_type, payload) when is_binary(object_type) and is_map(payload) do
    request("fedify.translate.v1", %{object_type: object_type, payload: payload})
  end

  @doc "Sign an outbound HTTP request. See `deno/handlers/sign_delivery.ts` for the payload shape."
  @spec sign(map()) :: {:ok, term()} | {:error, term()}
  def sign(payload) when is_map(payload) do
    request("fedify.sign.v1", payload)
  end

  @doc "Verify an incoming signed HTTP request. See `deno/handlers/verify.ts` for the payload shape."
  @spec verify(map()) :: {:ok, term()} | {:error, term()}
  def verify(payload) when is_map(payload) do
    request("fedify.verify.v1", payload)
  end

  @doc "Round-trip health check via `fedify.ping.v1`."
  @spec ping() :: :ok | {:ok, binary()} | {:error, term()}
  def ping do
    case Gnat.request(:gnat, "fedify.ping.v1", "pong", receive_timeout: @timeout) do
      {:ok, %{body: "pong"}} -> :ok
      {:ok, %{body: other}} -> {:ok, other}
      {:error, _} = err -> err
    end
  end

  defp request(subject, payload) do
    body = Jason.encode!(payload)

    case Gnat.request(:gnat, subject, body, receive_timeout: @timeout) do
      {:ok, %{body: reply}} ->
        case Jason.decode(reply) do
          {:ok, %{"ok" => true, "data" => data}} -> {:ok, data}
          {:ok, %{"ok" => false, "error" => error}} -> {:error, error}
          {:ok, other} -> {:error, {:invalid_envelope, other}}
          {:error, _} = err -> err
        end

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, _} = err ->
        err
    end
  end
end
