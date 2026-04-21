# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Views.MastodonAccount do
  @moduledoc """
  Render an `Account` (or a hydrated map projection) into Mastodon
  v1 Account JSON shape.

  Two render modes:
    * `render/2` — public Account (no `source` block, no scopes)
    * `render_credential/3` — CredentialAccount returned from
      `/api/v1/accounts/verify_credentials`. Includes `source` and
      Mastodon-specific oauth metadata.

  Counts are passed in separately because they're computed by a
  cached gateway helper and we don't want to recount on every
  render. `nil` counts render as `0`.
  """

  alias SukhiApi.Views.Id

  @doc """
  Render a single account.

  `account` may be an `Account` struct or a plain map carrying the
  same keys; this is what comes off `:rpc` since structs survive the
  hop as maps.

  `counts` is `%{followers: int, following: int, statuses: int}` (any
  missing key defaults to 0).
  """
  @spec render(map() | nil, map()) :: map() | nil
  def render(account, counts \\ %{})
  def render(nil, _counts), do: nil

  def render(account, counts) do
    domain = Application.get_env(:sukhi_api, :domain, "localhost:4000")
    username = account.username
    actor_uri = "https://#{domain}/users/#{username}"

    %{
      id: Id.encode(account.id),
      username: username,
      acct: username,
      display_name: account.display_name || username,
      locked: false,
      bot: Map.get(account, :is_bot, false) || false,
      discoverable: true,
      group: false,
      created_at: format_dt(Map.get(account, :created_at)),
      note: Map.get(account, :summary) || "",
      url: actor_uri,
      uri: actor_uri,
      avatar: Map.get(account, :avatar_url),
      avatar_static: Map.get(account, :avatar_url),
      header: Map.get(account, :banner_url),
      header_static: Map.get(account, :banner_url),
      followers_count: Map.get(counts, :followers, 0),
      following_count: Map.get(counts, :following, 0),
      statuses_count: Map.get(counts, :statuses, 0),
      last_status_at: nil,
      emojis: [],
      fields: []
    }
  end

  @doc """
  Render `verify_credentials`-shaped CredentialAccount: extends a
  public Account with `source`, `role`, and a `scopes` echo.
  """
  @spec render_credential(map(), map(), [String.t()]) :: map()
  def render_credential(account, counts, scopes) do
    base = render(account, counts)

    Map.merge(base, %{
      source: %{
        privacy: "public",
        sensitive: false,
        language: nil,
        note: Map.get(account, :summary) || "",
        fields: [],
        follow_requests_count: 0
      },
      role:
        if Map.get(account, :is_admin, false) do
          %{id: "1", name: "admin", permissions: "1", color: "", highlighted: true}
        else
          %{id: "0", name: "user", permissions: "0", color: "", highlighted: false}
        end,
      scopes: scopes
    })
  end

  @spec render_list([map()], map()) :: [map()]
  def render_list(accounts, counts_by_id \\ %{}) when is_list(accounts) do
    Enum.map(accounts, fn a -> render(a, Map.get(counts_by_id, a.id, %{})) end)
  end

  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(_), do: nil
end
