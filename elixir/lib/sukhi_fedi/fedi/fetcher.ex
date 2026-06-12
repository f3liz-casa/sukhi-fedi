# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Fedi.Fetcher do
  @moduledoc """
  Remote ActivityPub document fetch (`fedify.fetch.v1`), optionally
  HTTP-signed for Mastodon Secure Mode / Misskey auth-fetch peers.

  Every hop — including each redirect target — passes
  `Federation.UrlGuard.safe?/1`, preserving the SSRF property the
  fedify document loader provided. Redirects are followed manually so
  the signature can be recomputed per hop (it covers
  `(request-target)`, which changes with the URL).

  Signing always uses draft-cavage; that is what the entire current
  fediverse accepts on GET. (fedify could double-knock RFC 9421 — no
  known peer requires it, so we don't carry that machinery.)
  """

  require Logger

  alias SukhiFedi.Cache.Ets
  alias SukhiFedi.Federation.UrlGuard
  alias SukhiFedi.Fedi.{HttpSignature, JWK}

  @accept ~s(application/activity+json, application/ld+json; profile="https://www.w3.org/ns/activitystreams")
  @max_redirects 5
  @receive_timeout 15_000
  @cache_table :fedi_documents
  @cache_ttl_seconds 6 * 3600

  @doc """
  Fetches an AP document. `sign_as` is `nil` or a
  `%{"keyId" => …, "privateJwk" => …}` map (the wire shape
  `Accounts.signing_identity/0` produces). Returns
  `{:ok, %{"document" => map}}` to match the Bun endpoint.
  """
  @spec fetch_document(String.t(), map() | nil) :: {:ok, map()} | {:error, term()}
  def fetch_document(uri, sign_as \\ nil) when is_binary(uri) do
    with {:ok, document} <- get_json(uri, signer(sign_as)) do
      {:ok, %{"document" => document}}
    end
  end

  @doc """
  Like `fetch_document/2` but unsigned and cached — used for signing-key
  lookups during inbound verification, where the same actor document is
  needed for every activity a peer delivers. `:fresh` bypasses the cache
  (the stale-key retry in `Fedi.Verifier`).
  """
  @spec fetch_cached(String.t(), [:fresh]) :: {:ok, map()} | {:error, term()}
  def fetch_cached(uri, opts \\ []) do
    if :fresh in opts do
      refresh(uri)
    else
      case Ets.get(@cache_table, uri) do
        {:ok, document} -> {:ok, document}
        :miss -> refresh(uri)
      end
    end
  end

  defp refresh(uri) do
    with {:ok, document} <- get_json(uri, nil) do
      Ets.put(@cache_table, uri, document, @cache_ttl_seconds)
      {:ok, document}
    end
  end

  # ── HTTP ─────────────────────────────────────────────────────────────────

  defp signer(%{"keyId" => key_id, "privateJwk" => jwk}) when is_map(jwk) do
    case JWK.private_key(jwk) do
      {:ok, private_key} ->
        {private_key, key_id}

      {:error, _} ->
        # A broken local key should not make remote fetch impossible;
        # fall back to the unsigned reach we had before keys existed.
        Logger.warning("fedi.fetch: signing key JWK is invalid, fetching unsigned")
        nil
    end
  end

  defp signer(_), do: nil

  defp get_json(url, signer, redirects_left \\ @max_redirects)

  defp get_json(_url, _signer, 0), do: {:error, :too_many_redirects}

  defp get_json(url, signer, redirects_left) do
    with :ok <- guard(url),
         {:ok, response} <- request(url, signer) do
      case response do
        %{status: status, headers: headers} when status in [301, 302, 303, 307, 308] ->
          case location(headers, url) do
            nil -> {:error, {:redirect_without_location, status}}
            next -> get_json(next, signer, redirects_left - 1)
          end

        %{status: 200, body: body} when is_map(body) ->
          {:ok, body}

        %{status: 200, body: body} when is_binary(body) ->
          JSON.decode(body)

        %{status: status} ->
          {:error, {:http_status, status}}
      end
    end
  end

  defp request(url, signer) do
    headers =
      case signer do
        nil -> %{"accept" => @accept}
        {private_key, key_id} -> HttpSignature.sign_get(url, private_key, key_id) |> Map.put("accept", @accept)
      end

    Req.get(url,
      headers: headers,
      redirect: false,
      finch: SukhiFedi.Finch,
      receive_timeout: @receive_timeout
    )
  end

  defp guard(url) do
    if UrlGuard.safe?(url), do: :ok, else: {:error, {:unsafe_url, url}}
  end

  defp location(headers, base) do
    case Map.get(headers, "location") do
      [value | _] -> base |> URI.merge(value) |> URI.to_string()
      value when is_binary(value) -> base |> URI.merge(value) |> URI.to_string()
      _ -> nil
    end
  end
end
