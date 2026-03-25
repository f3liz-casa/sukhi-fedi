# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.WebPush do
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
    |> Repo.insert(on_conflict: {:replace, [:account_id, :p256dh_key, :auth_key, :alerts, :updated_at]}, conflict_target: :endpoint)
  end

  def unsubscribe(endpoint) do
    Repo.delete_all(from p in PushSubscription, where: p.endpoint == ^endpoint)
  end

  def get_subscriptions(account_id) do
    Repo.all(from p in PushSubscription, where: p.account_id == ^account_id)
  end

  def send_notification(account_id, notification) do
    subscriptions = get_subscriptions(account_id)
    
    Enum.each(subscriptions, fn sub ->
      Task.start(fn ->
        payload = Jason.encode!(%{
          title: notification.title,
          body: notification.body,
          icon: notification.icon,
          data: notification.data
        })
        
        # Use web-push library (would need to add dependency)
        # WebPush.send_notification(sub.endpoint, payload, sub.p256dh_key, sub.auth_key)
      end)
    end)
  end
end
