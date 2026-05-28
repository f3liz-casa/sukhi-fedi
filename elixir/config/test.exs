# SPDX-License-Identifier: AGPL-3.0-or-later
import Config

config :sukhi_fedi, SukhiFedi.Repo,
  database: "sukhi_fedi_test",
  port: String.to_integer(System.get_env("DB_PORT", "15432")),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :sukhi_fedi, Oban, testing: :inline

config :sukhi_fedi, :nats,
  host: System.get_env("NATS_HOST", "127.0.0.1"),
  port: String.to_integer(System.get_env("NATS_PORT", "14222"))

# Deterministic admin-session signing key for tests.
config :sukhi_fedi, :secret_key_base,
  "test_key_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Point ex_aws at the rustfs container from docker-compose.test.yml.
config :ex_aws, :s3,
  scheme: "http://",
  host: System.get_env("S3_HOST", "127.0.0.1"),
  port: String.to_integer(System.get_env("S3_PORT", "19000")),
  region: "us-east-1"

config :ex_aws,
  access_key_id: "testaccess",
  secret_access_key: "testsecret",
  json_codec: Jason

config :sukhi_fedi, :s3, bucket: "media-test", enabled: true
