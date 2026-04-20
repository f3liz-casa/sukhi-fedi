# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.GatewayRpc do
  @moduledoc """
  Thin wrapper over `:rpc.call/5` for plugin capabilities that need
  to read or mutate data owned by the gateway BEAM node
  (`SukhiFedi.*` context modules).

  The gateway node is read from `Application.get_env(:sukhi_api, :gateway_node)`,
  which in production is supplied via the `GATEWAY_NODE` env var
  (see `api/config/runtime.exs`).

  Returns:
    * `{:ok, value}`       — on a successful call
    * `{:error, {:badrpc, reason}}` — gateway unreachable or crashed
    * `{:error, :not_connected}`    — Erlang distribution disabled /
                                      no node configured

  Capabilities should translate these into HTTP responses (503 for
  transport issues, 4xx/5xx for domain failures).
  """

  @default_timeout 5_000

  @spec call(module(), atom(), [term()], pos_integer()) ::
          {:ok, term()} | {:error, term()}
  def call(mod, fun, args, timeout \\ @default_timeout)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    case gateway_node() do
      nil ->
        {:error, :not_connected}

      node ->
        _ = maybe_connect(node)

        case :rpc.call(node, mod, fun, args, timeout) do
          {:badrpc, reason} -> {:error, {:badrpc, reason}}
          other -> {:ok, other}
        end
    end
  end

  defp gateway_node do
    case Application.get_env(:sukhi_api, :gateway_node) do
      nil -> nil
      n when is_atom(n) -> n
      n when is_binary(n) -> String.to_atom(n)
    end
  end

  # `Node.connect/1` is idempotent; once we're connected it returns true
  # quickly. Failures become `false` / `:ignored` which we tolerate —
  # the following `:rpc.call` will surface a `{:badrpc, :nodedown}`.
  defp maybe_connect(node) do
    case :net_kernel.connect_node(node) do
      true -> :ok
      _ -> :ignored
    end
  rescue
    _ -> :ignored
  end
end
