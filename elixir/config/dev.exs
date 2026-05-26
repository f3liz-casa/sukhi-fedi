# SPDX-License-Identifier: AGPL-3.0-or-later
import Config

config :sukhi_fedi, SukhiFedi.Repo,
  database: "sukhi_fedi_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Stable dev value so the admin session cookie keeps working across
# `iex -S mix` restarts. NEVER use this in prod — prod reads from
# the SECRET_KEY_BASE env var (see runtime.exs).
config :sukhi_fedi, :secret_key_base,
  "dev_only_key_NOT_FOR_PRODUCTION_use_openssl_rand_hex_64_in_prod_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Dev runs over plain HTTP (no kamal-proxy TLS), so the secure cookie
# flag would prevent the session from being set at all.
config :sukhi_fedi, :admin_session_secure, false
