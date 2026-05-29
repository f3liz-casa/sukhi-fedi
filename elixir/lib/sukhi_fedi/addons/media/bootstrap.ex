# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addons.Media.Bootstrap do
  @moduledoc """
  起動時に S3 bucket の存在だけ確かめる。rustfs は最初の boot で空
  なので、HeadBucket → 404 → CreateBucket、という流れ。Bucket がすで
  にあるとき、`put_bucket` は 409 を返すので `bucket_already_owned_by_you`
  は成功扱いにする。
  """

  require Logger

  @doc """
  Idempotent。rustfs が落ちていれば warning だけ吐いて諦める ─ uploads
  が来たときに persist_bytes が改めて失敗するので、起動を止める意味は
  薄い。
  """
  @spec ensure_bucket() :: :ok | {:error, term()}
  def ensure_bucket do
    unless enabled?() do
      Logger.info("media bootstrap: S3 not configured, skipping bucket check")
      :ok
    else
      # Both the media bucket and the inbound-archive bucket (Q10) live in
      # the same rustfs accessory; ensure each exists.
      [bucket(), inbound_bucket()]
      |> Enum.uniq()
      |> Enum.each(&ensure_one/1)
    end
  end

  defp ensure_one(bucket) do
    case ExAws.S3.head_bucket(bucket) |> ExAws.request() do
      {:ok, _} ->
        Logger.info("media bootstrap: bucket #{inspect(bucket)} exists")
        :ok

      {:error, {:http_error, 404, _}} ->
        create(bucket)

      {:error, {:http_error, 301, _}} ->
        # Region mismatch (most clients return 301 for wrong-region).
        # We pin region in runtime.exs, so this only happens against a
        # real AWS S3 misconfig — log and continue.
        Logger.warning("media bootstrap: bucket #{inspect(bucket)} 301 — region mismatch?")
        :ok

      {:error, reason} ->
        Logger.warning(
          "media bootstrap: head_bucket failed reason=#{inspect(reason)} — will retry on first upload"
        )

        {:error, reason}
    end
  end

  defp create(bucket) do
    case ExAws.S3.put_bucket(bucket, region()) |> ExAws.request() do
      {:ok, _} ->
        Logger.info("media bootstrap: created bucket #{inspect(bucket)}")
        :ok

      {:error, {:http_error, 409, _}} ->
        :ok

      {:error, reason} ->
        Logger.warning("media bootstrap: put_bucket failed reason=#{inspect(reason)}")
        {:error, reason}
    end
  end

  defp enabled?, do: Application.get_env(:sukhi_fedi, :s3, [])[:enabled] == true
  defp bucket, do: Application.get_env(:sukhi_fedi, :s3, [])[:bucket] || "media"

  defp inbound_bucket,
    do: Application.get_env(:sukhi_fedi, :s3, [])[:inbound_bucket] || "inbound"

  defp region do
    case Application.get_env(:ex_aws, :s3) do
      list when is_list(list) -> Keyword.get(list, :region, "us-east-1")
      _ -> "us-east-1"
    end
  end
end
