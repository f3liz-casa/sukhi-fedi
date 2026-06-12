# SPDX-License-Identifier: AGPL-3.0-or-later
import Config

# Public-facing domain used in nodeinfo/webfinger/ActivityPub URLs.
# In prod, fetch_env! crashes the release on a missing DOMAIN rather than
# silently minting localhost:4000 URIs into outbound IDs and keyIds.
if config_env() == :prod do
  config :sukhi_fedi, :domain, System.fetch_env!("DOMAIN")
else
  config :sukhi_fedi, :domain, System.get_env("DOMAIN", "localhost:4000")
end

# Addon selection.
#   ENABLED_ADDONS: comma list of ids, or "all" (default).
#   ADDON_PRESETS:  comma list of preset ids (see SukhiFedi.Addon.Presets).
#                   Expanded and unioned with ENABLED_ADDONS.
#   DISABLE_ADDONS: comma list of ids to always exclude (deny-list wins).
presets =
  System.get_env("ADDON_PRESETS", "")
  |> String.split(",", trim: true)
  |> Enum.map(&String.to_atom/1)

# When ADDON_PRESETS is set, it becomes the effective allowlist (union
# with any explicit ENABLED_ADDONS list). ENABLED_ADDONS=all only wins
# if it was *explicitly* set; the implicit default ("all" when unset)
# yields to the preset so operators who pick a preset aren't surprised
# by every addon silently turning on.
enabled_addons =
  case {System.get_env("ENABLED_ADDONS"), presets} do
    {nil, []} ->
      :all

    {nil, ids} ->
      SukhiFedi.Addon.Presets.expand(ids)

    {"all", _} ->
      :all

    {"", []} ->
      :all

    {"", ids} ->
      SukhiFedi.Addon.Presets.expand(ids)

    {csv, ids} ->
      explicit = csv |> String.split(",", trim: true) |> Enum.map(&String.to_atom/1)
      Enum.uniq(SukhiFedi.Addon.Presets.expand(ids) ++ explicit)
  end

disabled_addons =
  System.get_env("DISABLE_ADDONS", "")
  |> String.split(",", trim: true)
  |> Enum.map(&String.to_atom/1)

config :sukhi_fedi, :enabled_addons, enabled_addons
config :sukhi_fedi, :disabled_addons, disabled_addons

# ── Object storage (S3-compatible, rustfs in prod) ───────────────────────
# media.ex の uploads はこの bucket に PutObject される。endpoint /
# 認証情報が無い env(test / 素の dev)では設定しない ─ persist_bytes が
# {:error, :not_configured} を返す。
endpoint = System.get_env("S3_ENDPOINT")

if endpoint do
  uri = URI.parse(endpoint)
  scheme = "#{uri.scheme}://"
  port = uri.port || if(uri.scheme == "https", do: 443, else: 80)

  config :ex_aws, :s3,
    scheme: scheme,
    host: uri.host,
    port: port,
    region: System.get_env("S3_REGION", "us-east-1")

  config :ex_aws,
    access_key_id: System.fetch_env!("S3_ACCESS_KEY_ID"),
    secret_access_key: System.fetch_env!("S3_SECRET_ACCESS_KEY"),
    json_codec: Jason

  config :sukhi_fedi, :s3,
    bucket: System.get_env("S3_BUCKET", "media"),
    inbound_bucket: System.get_env("S3_INBOUND_BUCKET", "inbound"),
    outbound_bucket: System.get_env("S3_OUTBOUND_BUCKET", "outbound"),
    enabled: true
else
  config :sukhi_fedi, :s3, enabled: false
end

if config_env() == :prod do
  config :sukhi_fedi, SukhiFedi.Repo,
    database: System.get_env("DB_NAME", "sukhi_fedi"),
    username: System.fetch_env!("DB_USER"),
    password: System.fetch_env!("DB_PASS"),
    hostname: System.get_env("DB_HOST", "localhost"),
    pool_size: String.to_integer(System.get_env("DB_POOL_SIZE", "10"))

  config :sukhi_fedi, :nats,
    host: System.get_env("NATS_HOST", "127.0.0.1"),
    port: String.to_integer(System.get_env("NATS_PORT", "4222"))

  # Cookie-signing key for the admin web UI session. Must be stable
  # across deploys — rotating invalidates every logged-in admin
  # session. Generate with `openssl rand -hex 64`.
  config :sukhi_fedi, :secret_key_base, System.fetch_env!("SECRET_KEY_BASE")

  # Distributed-Erlang plugin nodes reachable via `:rpc`.
  # Comma-separated list of `<name>@<host>` atoms. Nodes not reachable at
  # request time are skipped; if none are reachable, `/api/v1/*` returns
  # 503. Example: `PLUGIN_NODES=api@api,api_admin@api-admin`.
  config :sukhi_fedi, :plugin_nodes,
    System.get_env("PLUGIN_NODES", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.to_atom/1)

  # Oban monitor queue concurrency override. NodeInfo polling fans out
  # one job per monitored instance; on a 1 GB box 5 parallel Finch
  # requests + JSON decode buffers is more than we want resident.
  # Shallow-merges with the compile-time Oban config — `:repo` and
  # `:plugins` (Cron) are inherited unchanged.
  config :sukhi_fedi, Oban,
    queues: [monitor: String.to_integer(System.get_env("OBAN_MONITOR_CONCURRENCY", "5"))]
end
