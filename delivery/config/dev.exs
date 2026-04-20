# SPDX-License-Identifier: AGPL-3.0-or-later
import Config

config :sukhi_delivery, SukhiDelivery.Repo,
  database: "sukhi_fedi_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
