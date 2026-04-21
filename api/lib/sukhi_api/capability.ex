# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capability do
  @moduledoc """
  Behaviour for plugin capability modules.

  A capability declares a set of HTTP-shaped routes. When the module is
  compiled into the `:sukhi_api` application, the `SukhiApi.Registry`
  discovers it via a persistent module attribute — no explicit wiring
  or registration is required.

  ## Adding an endpoint

      # lib/sukhi_api/capabilities/whoami.ex
      defmodule SukhiApi.Capabilities.Whoami do
        use SukhiApi.Capability

        @impl true
        def routes, do: [{:get, "/api/v1/whoami", &whoami/1}]

        def whoami(_req) do
          {:ok,
           %{
             status: 200,
             body: Jason.encode!(%{name: "anon"}),
             headers: [{"content-type", "application/json"}]
           }}
        end
      end

  ## Authenticated endpoints

  Append a keyword list as a 4th element to require an OAuth bearer
  token. The router verifies the token via `SukhiFedi.OAuth.verify_bearer/1`
  on the gateway, checks scope, and exposes the bound account on
  `req[:assigns]`:

      def routes do
        [{:get, "/api/v1/accounts/verify_credentials", &show/1, scope: "read:accounts"}]
      end

      def show(req) do
        %{current_account: account} = req[:assigns]
        # …
      end

  Missing token → 401, scope mismatch → 403, gateway unreachable → 503.
  3-tuple routes remain unauthenticated.

  ## Removing an endpoint

  Delete the file. No other changes needed.

  ## Request / response shape

    * Request  — `%{method: String.t, path: String.t, query: String.t,
                    headers: [{String.t, String.t}], body: binary}`
    * Response — `{:ok, %{status: pos_integer, body: iodata,
                          headers: [{String.t, String.t}]}}`
  """

  @type method :: :get | :post | :put | :delete | :patch
  @type request :: %{
          required(:method) => String.t(),
          required(:path) => String.t(),
          optional(:query) => String.t(),
          optional(:headers) => [{String.t(), String.t()}],
          optional(:body) => binary(),
          optional(:assigns) => map()
        }
  @type response :: %{
          required(:status) => pos_integer(),
          required(:body) => iodata(),
          required(:headers) => [{String.t(), String.t()}]
        }
  @type handler :: (request() -> {:ok, response()} | {:error, term()})
  @type route ::
          {method(), String.t(), handler()}
          | {method(), String.t(), handler(), keyword()}

  @callback routes() :: [route()]

  @doc """
  `use SukhiApi.Capability` registers the module for discovery.

  Pass `addon: :some_id` to bind the capability to a specific gateway
  addon — when `ENABLED_ADDONS` does not include that id, the
  capability's routes are skipped. Capabilities without `:addon` are
  treated as core (always active).
  """
  defmacro __using__(opts) do
    addon = Keyword.get(opts, :addon)

    quote bind_quoted: [addon: addon] do
      @behaviour SukhiApi.Capability
      Module.register_attribute(__MODULE__, :sukhi_api_capability, persist: true)
      Module.register_attribute(__MODULE__, :sukhi_api_capability_addon, persist: true)
      @sukhi_api_capability true
      @sukhi_api_capability_addon addon
    end
  end
end
