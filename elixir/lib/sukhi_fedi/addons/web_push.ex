# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addons.WebPush do
  @moduledoc "Web Push addon — browser push notifications."

  use SukhiFedi.Addon, id: :web_push

  import Ecto.Query
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.PushSubscription

  def subscribe(account_id, endpoint, p256dh_key, auth_key, alerts \\ %{}) do
    %PushSubscription{
      account_id: account_id,
      endpoint: endpoint,
      p256dh_key: p256dh_key,
      auth_key: auth_key,
      alerts: alerts
    }
    |> Repo.insert(
      on_conflict: {:replace, [:account_id, :p256dh_key, :auth_key, :alerts, :updated_at]},
      conflict_target: :endpoint
    )
  end

  def unsubscribe(endpoint) do
    Repo.delete_all(from p in PushSubscription, where: p.endpoint == ^endpoint)
  end

  def get_subscriptions(account_id) do
    Repo.all(from p in PushSubscription, where: p.account_id == ^account_id)
  end

  def send_notification(account_id, _notification) do
    # Placeholder until a push-web library is wired up. Subscriptions are
    # persisted; delivery is a future task.
    _ = get_subscriptions(account_id)
    :ok
  end
end
