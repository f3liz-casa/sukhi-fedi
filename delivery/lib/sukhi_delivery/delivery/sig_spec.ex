# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Delivery.SigSpec do
  @moduledoc """
  Per-host HTTP-signature spec, learned by double-knocking.

  The fediverse is mid-migration from draft-cavage-http-signatures to
  RFC 9421. Fedify-based servers (hackers.pub, Hollo) already prefer
  RFC 9421; the Mastodon family is adding it. We can't know what a host
  speaks until we try, so the delivery worker "double-knocks": POST with
  one spec, and if the inbox answers a signature-rejection status
  (`knock?/1`), re-sign once with the other spec. Whichever the host
  accepts is remembered here, so steady state is one POST per delivery.

  The first guess defaults to **RFC 9421** — the direction the ecosystem
  is moving. This costs a cavage-only peer one extra knock on the first
  delivery and once per TTL afterward, but it buys the property that
  matters: when a peer that used to speak only cavage starts accepting
  RFC 9421, we follow it automatically. The learned value expires after
  a week, so on the next re-learn we try RFC 9421 again and promote the
  host the moment it's ready — no manual flush, no permanent lock-in to
  the old spec. (Defaulting to cavage would do the opposite: a host that
  gained RFC 9421 support would stay pinned to cavage forever, because
  every re-learn would try cavage first and succeed.)

  This is the single source of truth for "which signature spec for this
  host" (CODE_STYLE §3): the worker only asks here and reports back what
  was accepted.
  """

  alias SukhiDelivery.Cache.Ets

  @table :delivery_httpsig_spec
  # The default spec to try first, and the direction we re-probe toward.
  # RFC 9421 first means a peer that adds RFC 9421 support is promoted on
  # the next re-learn instead of being pinned to cavage.
  @default_spec :rfc9421
  # A learned spec expires within a week: short enough that a migrating
  # peer is picked up promptly, long enough that a cavage-only peer pays
  # the extra knock only ~once a week.
  @ttl_seconds 7 * 24 * 60 * 60

  @type spec :: :cavage | :rfc9421

  @doc "The spec to try first for `host`: the learned value, else RFC 9421."
  @spec spec_for(String.t() | nil) :: spec()
  def spec_for(host) when is_binary(host) do
    case Ets.get(@table, host) do
      {:ok, spec} -> spec
      :miss -> @default_spec
    end
  end

  def spec_for(_), do: @default_spec

  @doc "Remember that `host` accepted `spec`."
  @spec learn(String.t() | nil, spec()) :: :ok
  def learn(host, spec) when is_binary(host) and spec in [:cavage, :rfc9421] do
    Ets.put(@table, host, spec, @ttl_seconds)
    :ok
  end

  def learn(_, _), do: :ok

  @doc "The other spec — what to re-sign with when the first is rejected."
  @spec alt(spec()) :: spec()
  def alt(:cavage), do: :rfc9421
  def alt(:rfc9421), do: :cavage

  @doc """
  Statuses that mean "maybe we signed with the wrong spec" and are worth
  one knock. Only the signature-rejection codes: 401 (the usual) and 400
  (some servers reject a malformed/unexpected signature this way). 403
  (blocked), 404 (no inbox), 410 (gone), 429 (rate) and 5xx are NOT spec
  problems — knocking there would just double every POST.
  """
  @spec knock?(integer()) :: boolean()
  def knock?(status), do: status in [400, 401]
end
