# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.AdminAuth do
  @moduledoc """
  Admin-only gate layered on top of the router's OAuth scope check.

  The router already verifies `admin:read` / `admin:write` and loads
  `current_account` via `SukhiFedi.OAuth.verify_bearer/1`. This helper
  additionally requires the bound account's `is_admin` flag. It is
  called at the top of every admin capability handler; unlike the
  scope check, which lives in the router, this lives per-handler so
  the router stays independent of role semantics.
  """

  @spec require_admin(map()) :: {:ok, map()} | {:error, :forbidden}
  def require_admin(%{assigns: %{current_account: %{is_admin: true} = account}}),
    do: {:ok, account}

  def require_admin(_req), do: {:error, :forbidden}
end
