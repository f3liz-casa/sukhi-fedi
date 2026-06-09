# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Federation.RemoteAccounts do
  @moduledoc """
  Upsert remote ActivityPub actors into the local `accounts` directory
  as **shadow rows** (`domain IS NOT NULL`).

  Shadow rows are what lets `Follow`/`Note`/`Reaction` etc. keep their
  cheap integer FK to `accounts.id` while still pointing at a remote
  Person. There is no public-key material *we own* on a shadow row —
  `public_key_pem` here is the *remote's* key, used by the inbound
  signature verifier, not the outbound signer.
  """

  alias SukhiFedi.AP.Emojis
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Account

  @doc """
  Upsert an Account from a parsed ActivityPub Actor JSON map.

  Idempotent on `actor_uri`. Returns `{:ok, account}` on success, or
  `{:error, reason}` on malformed input.

  When `expected_uri` is given (the URL we actually fetched), the actor's
  own `id` host must match it. This stops a server at evil.example from
  serving a document claiming `id: https://good.example/users/alice` and
  impersonating / overwriting that actor's shadow row.
  """
  @spec upsert_from_actor_json(map(), String.t() | nil) ::
          {:ok, Account.t()} | {:error, term()}
  def upsert_from_actor_json(actor_json, expected_uri \\ nil)

  def upsert_from_actor_json(actor_json, expected_uri) when is_map(actor_json) do
    with {:ok, actor_uri} <- fetch(actor_json, "id"),
         :ok <- check_expected_host(actor_uri, expected_uri),
         {:ok, username} <- fetch_username(actor_json),
         {:ok, domain} <- fetch_domain(actor_uri) do
      attrs = %{
        actor_uri: actor_uri,
        username: username,
        domain: domain,
        display_name: actor_json["name"] || username,
        summary: actor_json["summary"] || "",
        emojis: Emojis.from_tag(actor_json["tag"]),
        inbox_url: actor_json["inbox"],
        shared_inbox_url: shared_inbox(actor_json),
        public_key_id: get_in(actor_json, ["publicKey", "id"]),
        public_key_pem: get_in(actor_json, ["publicKey", "publicKeyPem"]),
        avatar_url: image_url(actor_json["icon"]),
        banner_url: image_url(actor_json["image"]),
        last_fetched_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      case Repo.get_by(Account, actor_uri: actor_uri) do
        nil -> %Account{} |> Account.changeset_remote(attrs) |> Repo.insert()
        %Account{} = existing -> existing |> Account.changeset_remote(attrs) |> Repo.update()
      end
    end
  end

  def upsert_from_actor_json(_, _), do: {:error, :invalid_actor}

  defp check_expected_host(_actor_uri, nil), do: :ok

  defp check_expected_host(actor_uri, expected_uri) do
    case {host_of(actor_uri), host_of(expected_uri)} do
      {h, h} when is_binary(h) -> :ok
      _ -> {:error, :id_host_mismatch}
    end
  end

  defp host_of(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{host: h} when is_binary(h) and h != "" -> String.downcase(h)
      _ -> nil
    end
  end

  defp host_of(_), do: nil

  defp fetch(map, key) do
    case Map.get(map, key) do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, {:missing, key}}
    end
  end

  defp fetch_username(actor_json) do
    case Map.get(actor_json, "preferredUsername") do
      v when is_binary(v) and v != "" ->
        {:ok, v}

      _ ->
        # Fall back to the last path segment of the id. Misskey/Mastodon
        # always set preferredUsername; this is defensive.
        with {:ok, uri} <- fetch(actor_json, "id"),
             %URI{path: path} when is_binary(path) <- URI.parse(uri),
             [_ | _] = parts <- String.split(path, "/", trim: true) do
          {:ok, List.last(parts)}
        else
          _ -> {:error, :no_username}
        end
    end
  end

  defp fetch_domain(actor_uri) do
    case URI.parse(actor_uri) do
      %URI{host: host} when is_binary(host) and host != "" -> {:ok, host}
      _ -> {:error, :no_domain}
    end
  end

  defp shared_inbox(actor_json) do
    case get_in(actor_json, ["endpoints", "sharedInbox"]) do
      v when is_binary(v) -> v
      _ -> nil
    end
  end

  defp image_url(%{"url" => url}) when is_binary(url), do: url
  defp image_url(url) when is_binary(url), do: url
  defp image_url(_), do: nil
end
