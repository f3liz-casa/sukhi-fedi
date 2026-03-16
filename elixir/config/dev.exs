# SPDX-License-Identifier: MPL-2.0
import Config

config :sukhi_fedi, SukhiFedi.Repo,
  database: "sukhi_fedi_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
