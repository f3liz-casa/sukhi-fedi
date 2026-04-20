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
          optional(:body) => binary()
        }
  @type response :: %{
          required(:status) => pos_integer(),
          required(:body) => iodata(),
          required(:headers) => [{String.t(), String.t()}]
        }
  @type handler :: (request() -> {:ok, response()} | {:error, term()})
  @type route :: {method(), String.t(), handler()}

  @callback routes() :: [route()]

  defmacro __using__(_opts) do
    quote do
      @behaviour SukhiApi.Capability
      Module.register_attribute(__MODULE__, :sukhi_api_capability, persist: true)
      @sukhi_api_capability true
    end
  end
end
