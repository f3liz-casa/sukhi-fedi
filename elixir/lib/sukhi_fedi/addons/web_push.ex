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

  @doc """
  Mastodon's API expects one subscription per access token, but our
  schema is per (account, endpoint). For now we surface the most
  recent subscription for the account — clients re-POST whenever the
  browser hands them a new endpoint, so "newest" is a reasonable
  proxy.
  """
  def get_subscription_for(account_id) when is_integer(account_id) do
    Repo.one(
      from p in PushSubscription,
        where: p.account_id == ^account_id,
        order_by: [desc: p.id],
        limit: 1
    )
  end

  @doc """
  Server VAPID key the client needs to encrypt push messages with.
  Returned by `GET /api/v1/instance` (under `configuration.urls`) and
  by `POST /api/v1/push/subscription` on success. Reads from
  `:sukhi_fedi, :vapid_public_key` config; nil if unconfigured.
  """
  def server_key, do: Application.get_env(:sukhi_fedi, :vapid_public_key)

  def send_notification(account_id, _notification) do
    # Placeholder until a push-web library is wired up. Subscriptions are
    # persisted; delivery is a future task.
    _ = get_subscriptions(account_id)
    :ok
  end
end
