# SPDX-License-Identifier: MPL-2.0
import Config

config :sukhi_fedi, SukhiFedi.Repo,
  database: System.get_env("DB_NAME", "sukhi_fedi"),
  username: System.get_env("DB_USER", "postgres"),
  password: System.get_env("DB_PASS", "postgres"),
  hostname: System.get_env("DB_HOST", "localhost"),
  pool_size: String.to_integer(System.get_env("DB_POOL_SIZE", "10"))
