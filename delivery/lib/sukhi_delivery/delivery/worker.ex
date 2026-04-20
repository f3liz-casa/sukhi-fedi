# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Delivery.Worker do
  @moduledoc """
  Oban worker that HTTP-POSTs a signed ActivityPub Activity to a remote
  inbox.

  Cross-node Oban: the gateway inserts jobs into the shared `oban_jobs`
  table with this module name as a string (`worker:
  "SukhiDelivery.Delivery.Worker"`); only the delivery node's Oban
  supervisor polls the `:delivery` queue, so only delivery nodes execute
  these jobs.

  Idempotency: when the job args include `"activity_id"`, the worker
  consults `delivery_receipts` and skips the POST if the same
  `(activity_id, inbox_url)` tuple has already been delivered. On success
  a receipt is recorded.

  Signing is delegated to `SukhiDelivery.Delivery.FedifyClient.sign/1`
  (NATS Micro → Bun/Fedify). If signing is unavailable (no key, service
  down) the POST goes out unsigned and remote servers will 401/403 —
  Oban retries with exponential backoff (max_attempts: 10).
  """

  use Oban.Worker, queue: :delivery, max_attempts: 10
  import Ecto.Query

  alias SukhiDelivery.{Repo, Delivery.FedifyClient}
  alias SukhiDelivery.Schema.{Object, Account, DeliveryReceipt}
  alias SukhiDelivery.Delivery.FollowersSync

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    inbox_url = args["inbox_url"]
    activity_id = args["activity_id"]

    if already_delivered?(activity_id, inbox_url) do
      :ok
    else
      do_deliver(args, activity_id, inbox_url)
    end
  end

  defp do_deliver(args, activity_id, inbox_url) do
    {body, actor_uri} = resolve_body_and_actor(args)

    base_headers = %{"content-type" => "application/activity+json"}

    sync_headers = resolve_sync_headers(args, actor_uri)

    headers =
      case sign_request(actor_uri, inbox_url, body) do
        {:ok, sig_headers} ->
          base_headers |> Map.merge(sync_headers) |> Map.merge(sig_headers)

        :skip ->
          Map.merge(base_headers, sync_headers)
      end

    case Req.post(inbox_url,
           body: body,
           headers: Enum.to_list(headers),
           finch: SukhiDelivery.Finch,
           connect_options: [timeout: 10_000],
           receive_timeout: 30_000
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        record_delivery(activity_id, inbox_url, "delivered")
        :ok

      {:ok, %{status: 410}} ->
        record_delivery(activity_id, inbox_url, "gone")
        :ok

      {:ok, %{status: status}} ->
        {:error, "unexpected status #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp resolve_body_and_actor(%{"object_id" => id}) do
    object = Repo.get!(Object, id)
    {Jason.encode!(object.raw_json), object.actor_id}
  end

  defp resolve_body_and_actor(%{"raw_json" => raw_json, "actor_uri" => actor_uri}) do
    {Jason.encode!(raw_json), actor_uri}
  end

  defp resolve_body_and_actor(%{"raw_json" => raw_json}) do
    {Jason.encode!(raw_json), nil}
  end

  defp resolve_sync_headers(%{"sync_header" => value}, _actor_uri) when is_binary(value) do
    %{"Collection-Synchronization" => value}
  end

  defp resolve_sync_headers(%{"sync_header" => nil}, _actor_uri), do: %{}

  defp resolve_sync_headers(_args, nil), do: %{}

  defp resolve_sync_headers(_args, actor_uri) do
    case FollowersSync.header_value(actor_uri) do
      nil -> %{}
      value -> %{"Collection-Synchronization" => value}
    end
  end

  defp sign_request(nil, _inbox, _body), do: :skip

  defp sign_request(actor_uri, inbox_url, body) do
    case get_private_key_jwk(actor_uri) do
      nil ->
        :skip

      jwk ->
        key_id = "#{actor_uri}#main-key"

        case FedifyClient.sign(%{
               actorUri: actor_uri,
               inbox: inbox_url,
               body: body,
               privateKeyJwk: jwk,
               keyId: key_id
             }) do
          {:ok, %{"headers" => sig_headers}} -> {:ok, sig_headers}
          _ -> :skip
        end
    end
  end

  defp get_private_key_jwk(actor_uri) when is_binary(actor_uri) do
    username =
      actor_uri
      |> URI.parse()
      |> Map.get(:path, "")
      |> String.split("/")
      |> List.last()

    case Repo.get_by(Account, username: username) do
      %Account{private_key_jwk: jwk} when not is_nil(jwk) -> jwk
      _ -> nil
    end
  end

  defp get_private_key_jwk(_), do: nil

  defp already_delivered?(nil, _inbox_url), do: false

  defp already_delivered?(activity_id, inbox_url) do
    Repo.exists?(
      from(r in DeliveryReceipt,
        where:
          r.activity_id == ^activity_id and r.inbox_url == ^inbox_url and
            r.status == "delivered"
      )
    )
  end

  defp record_delivery(nil, _inbox_url, _status), do: :ok

  defp record_delivery(activity_id, inbox_url, status) do
    %DeliveryReceipt{}
    |> DeliveryReceipt.changeset(%{
      activity_id: activity_id,
      inbox_url: inbox_url,
      status: status,
      delivered_at: DateTime.utc_now()
    })
    |> Repo.insert(on_conflict: :nothing)

    :ok
  end
end
