# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MastodonAccounts do
  @moduledoc """
  Mastodon `/api/v1/accounts/*` read surface plus
  `update_credentials` and `relationships`. Authenticated routes
  require an OAuth bearer token; public reads (`:id`, `lookup`,
  `:id/statuses`, `:id/followers`, `:id/following`) do not.
  """

  use SukhiApi.Capability, addon: :mastodon_api

  alias SukhiApi.{GatewayRpc, Pagination}
  alias SukhiApi.Views.{MastodonAccount, MastodonRelationship, MastodonStatus}

  @impl true
  def routes do
    [
      {:get, "/api/v1/accounts/verify_credentials", &verify_credentials/1,
       scope: "read:accounts"},
      {:patch, "/api/v1/accounts/update_credentials", &update_credentials/1,
       scope: "write:accounts"},
      {:get, "/api/v1/accounts/lookup", &lookup/1},
      {:get, "/api/v1/accounts/relationships", &relationships/1, scope: "read:follows"},
      {:get, "/api/v1/accounts/:id", &show/1},
      {:get, "/api/v1/accounts/:id/statuses", &statuses/1},
      {:get, "/api/v1/accounts/:id/followers", &followers/1},
      {:get, "/api/v1/accounts/:id/following", &following/1}
    ]
  end

  # ── verify_credentials ───────────────────────────────────────────────────

  def verify_credentials(req) do
    %{current_account: account, scopes: scopes} = req[:assigns]

    case account do
      nil ->
        # client_credentials grant — no end-user identity
        ok(403, %{error: "this endpoint requires a user-bound token"})

      %{} = a ->
        counts = counts_for(a.id)
        ok(200, MastodonAccount.render_credential(a, counts, scopes))
    end
  end

  # ── update_credentials ───────────────────────────────────────────────────

  def update_credentials(req) do
    %{current_account: account} = req[:assigns]

    case account do
      nil ->
        ok(403, %{error: "this endpoint requires a user-bound token"})

      %{id: id} ->
        attrs = decode_update_attrs(req)

        case GatewayRpc.call(SukhiFedi.Accounts, :update_credentials, [id, attrs]) do
          {:ok, {:ok, updated}} ->
            counts = counts_for(updated.id)
            ok(200, MastodonAccount.render_credential(updated, counts, req[:assigns][:scopes]))

          {:ok, {:error, :not_found}} ->
            ok(404, %{error: "account_not_found"})

          {:ok, {:error, {:validation, errors}}} ->
            ok(422, %{error: "validation_failed", details: errors})

          {:error, :not_connected} ->
            ok(503, %{error: "gateway_not_connected"})

          {:error, {:badrpc, reason}} ->
            ok(503, %{error: "gateway_rpc_failed", detail: inspect(reason)})

          _ ->
            ok(500, %{error: "internal_error"})
        end
    end
  end

  defp decode_update_attrs(req) do
    headers = req[:headers] || []
    ct = content_type(headers)

    cond do
      String.contains?(ct, "application/json") ->
        case Jason.decode(req[:body] || "") do
          {:ok, %{} = m} -> m
          _ -> %{}
        end

      String.contains?(ct, "application/x-www-form-urlencoded") ->
        URI.decode_query(req[:body] || "")

      true ->
        %{}
    end
  end

  # ── lookup ───────────────────────────────────────────────────────────────

  def lookup(req) do
    q = parse_query(req[:query])
    acct = q["acct"] || ""

    case GatewayRpc.call(SukhiFedi.Accounts, :lookup_by_acct, [acct]) do
      {:ok, {:ok, account}} ->
        ok(200, MastodonAccount.render(account, counts_for(account.id)))

      {:ok, {:error, :not_found}} ->
        ok(404, %{error: "account_not_found"})

      {:error, :not_connected} ->
        ok(503, %{error: "gateway_not_connected"})

      {:error, {:badrpc, reason}} ->
        ok(503, %{error: "gateway_rpc_failed", detail: inspect(reason)})
    end
  end

  # ── show ─────────────────────────────────────────────────────────────────

  def show(req) do
    id = req[:path_params]["id"]

    case GatewayRpc.call(SukhiFedi.Accounts, :get_account, [id]) do
      {:ok, {:ok, account}} ->
        ok(200, MastodonAccount.render(account, counts_for(account.id)))

      {:ok, {:error, :not_found}} ->
        ok(404, %{error: "account_not_found"})

      {:error, :not_connected} ->
        ok(503, %{error: "gateway_not_connected"})

      {:error, {:badrpc, reason}} ->
        ok(503, %{error: "gateway_rpc_failed", detail: inspect(reason)})
    end
  end

  # ── statuses ─────────────────────────────────────────────────────────────

  def statuses(req) do
    id = req[:path_params]["id"]

    with {:ok, int_id} <- parse_int(id),
         opts = parse_status_opts(req[:query]),
         {:ok, notes} when is_list(notes) <-
           GatewayRpc.call(SukhiFedi.Accounts, :list_statuses, [int_id, Map.to_list(opts)]) do
      body = Enum.map(notes, &MastodonStatus.render/1)
      headers = [{"content-type", "application/json"}]

      headers =
        case Pagination.link_header(
               "/api/v1/accounts/#{id}/statuses",
               notes,
               & &1.id,
               opts
             ) do
          nil -> headers
          link -> [link | headers]
        end

      {:ok, %{status: 200, body: Jason.encode!(body), headers: headers}}
    else
      {:error, :bad_int} ->
        ok(400, %{error: "invalid_id"})

      {:error, :not_connected} ->
        ok(503, %{error: "gateway_not_connected"})

      {:error, {:badrpc, reason}} ->
        ok(503, %{error: "gateway_rpc_failed", detail: inspect(reason)})

      _ ->
        ok(500, %{error: "internal_error"})
    end
  end

  defp parse_status_opts(q) do
    base = Pagination.parse_opts(q)
    parsed = parse_query(q)

    base
    |> Map.put(:exclude_replies, parsed["exclude_replies"] in ["true", "1"])
    |> Map.put(:exclude_reblogs, parsed["exclude_reblogs"] in ["true", "1"])
    |> Map.put(:only_media, parsed["only_media"] in ["true", "1"])
  end

  # ── followers / following ────────────────────────────────────────────────

  def followers(req) do
    id = req[:path_params]["id"]

    with {:ok, int_id} <- parse_int(id),
         {:ok, uris} when is_list(uris) <-
           GatewayRpc.call(SukhiFedi.Social, :list_followers, [int_id]) do
      ok(200, Enum.map(uris, &uri_only_account/1))
    else
      {:error, :bad_int} -> ok(400, %{error: "invalid_id"})
      {:error, :not_connected} -> ok(503, %{error: "gateway_not_connected"})
      {:error, {:badrpc, r}} -> ok(503, %{error: "gateway_rpc_failed", detail: inspect(r)})
      _ -> ok(500, %{error: "internal_error"})
    end
  end

  def following(req) do
    id = req[:path_params]["id"]

    with {:ok, int_id} <- parse_int(id),
         {:ok, %{} = account} <-
           account_by_id(int_id),
         actor_uri = local_actor_uri(account.username),
         {:ok, items} when is_list(items) <-
           GatewayRpc.call(SukhiFedi.Social, :list_following, [actor_uri]) do
      ok(200, Enum.map(items, fn item -> MastodonAccount.render(item, %{}) end))
    else
      {:error, :bad_int} -> ok(400, %{error: "invalid_id"})
      {:error, :not_found} -> ok(404, %{error: "account_not_found"})
      {:error, :not_connected} -> ok(503, %{error: "gateway_not_connected"})
      {:error, {:badrpc, r}} -> ok(503, %{error: "gateway_rpc_failed", detail: inspect(r)})
      _ -> ok(500, %{error: "internal_error"})
    end
  end

  defp account_by_id(int_id) do
    case GatewayRpc.call(SukhiFedi.Accounts, :get_account, [int_id]) do
      {:ok, {:ok, a}} -> {:ok, a}
      {:ok, {:error, :not_found}} -> {:error, :not_found}
      {:error, e} -> {:error, e}
    end
  end

  defp uri_only_account(uri) do
    # Followers list returns AP URIs (some of which may be remote and
    # not yet hydrated locally). Surface a minimal Account-shaped JSON
    # carrying just the id (= URI) and url. Mastodon clients tolerate
    # missing fields; PR-N can fan out webfinger lookups for richer data.
    %{
      id: uri,
      acct: uri,
      username: extract_username(uri),
      display_name: extract_username(uri),
      url: uri,
      uri: uri,
      avatar: nil,
      header: nil,
      followers_count: 0,
      following_count: 0,
      statuses_count: 0,
      created_at: nil,
      note: "",
      bot: false,
      locked: false
    }
  end

  defp extract_username(uri) when is_binary(uri) do
    uri |> URI.parse() |> Map.get(:path, "") |> to_string() |> Path.basename()
  end

  defp extract_username(_), do: ""

  # ── relationships ────────────────────────────────────────────────────────

  def relationships(req) do
    %{current_account: viewer} = req[:assigns]
    q = parse_query(req[:query])
    ids = extract_ids(q)

    case viewer do
      nil ->
        ok(403, %{error: "this endpoint requires a user-bound token"})

      %{} = v ->
        case GatewayRpc.call(SukhiFedi.Social, :list_relationships, [v, ids]) do
          {:ok, rels} when is_list(rels) ->
            ok(200, Enum.map(rels, &MastodonRelationship.render/1))

          {:error, :not_connected} ->
            ok(503, %{error: "gateway_not_connected"})

          {:error, {:badrpc, r}} ->
            ok(503, %{error: "gateway_rpc_failed", detail: inspect(r)})

          _ ->
            ok(500, %{error: "internal_error"})
        end
    end
  end

  defp extract_ids(query_map) do
    # Mastodon allows id[]=1&id[]=2 or id=1,2,3
    bracket = Map.get(query_map, "id[]", "")
    plain = Map.get(query_map, "id", "")

    raw =
      [bracket, plain]
      |> Enum.flat_map(fn s -> String.split(s || "", ",", trim: true) end)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    raw
    |> Enum.uniq()
    |> Enum.take(40)
    |> Enum.map(fn s ->
      case Integer.parse(s) do
        {n, ""} -> n
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  defp counts_for(account_id) when is_integer(account_id) do
    case GatewayRpc.call(SukhiFedi.Accounts, :counts_for, [account_id]) do
      {:ok, %{} = m} -> m
      _ -> %{followers: 0, following: 0, statuses: 0}
    end
  end

  defp local_actor_uri(username) do
    domain = Application.get_env(:sukhi_api, :domain, "localhost:4000")
    "https://#{domain}/users/#{username}"
  end

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> {:ok, n}
      _ -> {:error, :bad_int}
    end
  end

  defp parse_int(n) when is_integer(n), do: {:ok, n}
  defp parse_int(_), do: {:error, :bad_int}

  defp parse_query(nil), do: %{}
  defp parse_query(""), do: %{}
  defp parse_query(q) when is_binary(q), do: URI.decode_query(q)

  defp content_type(headers) do
    Enum.find_value(headers, "", fn {k, v} ->
      if String.downcase(to_string(k)) == "content-type", do: to_string(v), else: nil
    end)
  end

  defp ok(status, body) do
    {:ok,
     %{
       status: status,
       body: Jason.encode!(body),
       headers: [{"content-type", "application/json"}]
     }}
  end
end
