# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Changeset do
  @moduledoc """
  Changeset helpers shared across the context modules.
  """

  @doc """
  Flatten a changeset's errors into a `%{field => [message, ...]}` map,
  interpolating the `%{count}`-style placeholders Ecto leaves in the raw
  messages. Every context that surfaces validation errors to a caller
  formats them this way.
  """
  @spec errors(Ecto.Changeset.t()) :: %{atom() => [String.t()]}
  def errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end
end
