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

  # Outbound archive runs on the gateway (it owns the S3/zstd deps). We hand
  # it the bytes we actually sent by inserting a job on the shared oban_jobs
  # table, naming the gateway worker as a string — the reverse of how the
  # gateway enqueues us. See SukhiFedi.Federation.OutboundArchive.
  @archive_worker "SukhiFedi.Federation.OutboundArchive"
  @archive_queue "outbound_archive"

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    inbox_url = args["inbox_url"]
    activity_id = args["activity_id"]

    if already_delivered?(activity_id, inbox_url) do
      :ok
    else
      do_deliver(job, args, activity_id, inbox_url)
    end
  end

  defp do_deliver(job, args, activity_id, inbox_url) do
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

    require Logger

    # 署名検証失敗を追っている間だけ、POST 直前のヘッダ一覧と body の
    # 先頭バイトを出す。"Failed to verify the request signature."
    # の原因が「Req が User-Agent 等を上書きしている」「Digest が
    # ボディ実体と一致していない」のどちらなのかを切り分けたい。
    Logger.info(
      "delivery POST #{inbox_url} headers=#{inspect(Enum.to_list(headers))} body_first=#{inspect(String.slice(body, 0, 80))} body_bytes=#{byte_size(body)}"
    )

    case Req.post(inbox_url,
           body: body,
           headers: Enum.to_list(headers),
           finch: SukhiDelivery.Finch,
           receive_timeout: 30_000
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        record_delivery(activity_id, inbox_url, "delivered")
        archive_outbound(body, activity_id, inbox_url, actor_uri, "delivered", status)
        :ok

      {:ok, %{status: 410}} ->
        record_delivery(activity_id, inbox_url, "gone")
        archive_outbound(body, activity_id, inbox_url, actor_uri, "gone", 410)
        :ok

      {:ok, %{status: status, body: resp_body, headers: resp_headers}} ->
        # 401/403 を踏み続けるとき何が原因か見えるように、サーバから
        # 返ってきた body と頭の数行を残す。長すぎたら切り詰める。
        # [[fedify-401-diagnostic]]
        body_str =
          resp_body
          |> to_string()
          |> String.slice(0, 400)

        require Logger

        Logger.warning(
          "delivery #{status} from #{inbox_url}: body=#{inspect(body_str)} headers=#{inspect(Enum.take(resp_headers, 8))}"
        )

        maybe_archive_failure(job, body, activity_id, inbox_url, actor_uri, status)
        {:error, "unexpected status #{status}"}

      {:error, reason} ->
        maybe_archive_failure(job, body, activity_id, inbox_url, actor_uri, nil)
        {:error, inspect(reason)}
    end
  end

  # Keep the bytes we actually delivered. The body is content-addressed on
  # the gateway, so the same activity fanned out to many inboxes stores one
  # object; the index row is per (activity_id, inbox_url) with the outcome.
  # Enqueue is fire-and-forget — a failure here must never fail the delivery.
  defp archive_outbound(_body, nil, _inbox_url, _actor_uri, _status, _response_status), do: :ok

  defp archive_outbound(body, activity_id, inbox_url, actor_uri, status, response_status) do
    Oban.insert(
      SukhiDelivery.Oban,
      Oban.Job.new(
        %{
          body: body,
          activity_id: activity_id,
          inbox_url: inbox_url,
          actor_uri: actor_uri,
          status: status,
          response_status: response_status,
          delivered_at: DateTime.utc_now() |> DateTime.to_iso8601()
        },
        worker: @archive_worker,
        queue: @archive_queue
      )
    )

    :ok
  rescue
    # The delivery already happened — enqueueing the archive must never fail
    # it. In prod the row just lands on `outbound_archive` for the gateway to
    # run; this guards a transient DB hiccup. (It also covers test `:inline`,
    # where the gateway-only worker isn't loaded on the delivery node.)
    error ->
      require Logger
      Logger.warning("outbound archive enqueue failed: #{inspect(error)}")
      :ok
  end

  # A non-2xx / transport error is retried (returning {:error, _}), so only
  # archive it once, on the final attempt, as a "failed" record — audit cares
  # most about deliveries that never got through.
  defp maybe_archive_failure(
         %Oban.Job{attempt: attempt, max_attempts: max},
         body,
         activity_id,
         inbox_url,
         actor_uri,
         response_status
       )
       when attempt >= max do
    archive_outbound(body, activity_id, inbox_url, actor_uri, "failed", response_status)
  end

  defp maybe_archive_failure(_job, _body, _activity_id, _inbox_url, _actor_uri, _response_status),
    do: :ok

  defp resolve_body_and_actor(%{"object_id" => id}) do
    object = Repo.get!(Object, id)
    {JSON.encode!(object.raw_json), object.actor_id}
  end

  defp resolve_body_and_actor(%{"raw_json" => raw_json, "actor_uri" => actor_uri}) do
    {JSON.encode!(raw_json), actor_uri}
  end

  defp resolve_body_and_actor(%{"raw_json" => raw_json}) do
    {JSON.encode!(raw_json), nil}
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

        payload =
          %{
            actorUri: actor_uri,
            inbox: inbox_url,
            body: body,
            privateKeyJwk: jwk,
            keyId: key_id
          }
          |> maybe_put_algorithm(inbox_url)

        case FedifyClient.sign(payload) do
          {:ok, %{"headers" => sig_headers}} -> {:ok, sig_headers}
          _ -> :skip
        end
    end
  end

  # Per-host signing-spec override. hackers.pub (Fedify 2.x) keeps
  # returning "Failed to verify the request signature." on our valid
  # cavage signatures — same key, same digest, self-verifies fine.
  # Fedify accepts both cavage and rfc9421 on the verify side (picked
  # by the presence of the `Signature-Input` header), so try rfc9421
  # for that one origin and see if it changes the outcome.
  # [[fedify-401-diagnostic]]
  @rfc9421_inbox_hosts ["hackers.pub"]

  defp maybe_put_algorithm(payload, inbox_url) when is_binary(inbox_url) do
    case URI.parse(inbox_url) do
      %URI{host: host} when is_binary(host) ->
        if host in @rfc9421_inbox_hosts do
          Map.put(payload, :algorithm, "rfc9421")
        else
          payload
        end

      _ ->
        payload
    end
  end

  defp maybe_put_algorithm(payload, _), do: payload

  defp get_private_key_jwk(actor_uri) when is_binary(actor_uri) do
    username =
      actor_uri
      |> URI.parse()
      |> Map.get(:path, "")
      |> String.split("/")
      |> List.last()

    case SukhiDelivery.Accounts.by_local_username(username) do
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
