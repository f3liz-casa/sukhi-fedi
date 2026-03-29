# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Delivery.Worker do
  @moduledoc """
  Oban worker that HTTP POSTs a signed Activity JSON-LD to a remote inbox.
  """

  use Oban.Worker, queue: :delivery, max_attempts: 10

  alias SukhiFedi.{Repo, AP.Client}
  alias SukhiFedi.Schema.{Object, Account}
  alias SukhiFedi.Delivery.FollowersSync

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    inbox_url = args["inbox_url"]
    {body, actor_uri} = resolve_body_and_actor(args)

    base_headers = %{"content-type" => "application/activity+json"}

    # FEP-8fcf: attach Collection-Synchronization header for shared-inbox deliveries
    sync_headers =
      if actor_uri do
        case FollowersSync.header_value(actor_uri) do
          nil -> %{}
          value -> %{"Collection-Synchronization" => value}
        end
      else
        %{}
      end

    headers =
      case sign_request(actor_uri, inbox_url, body) do
        {:ok, sig_headers} -> base_headers |> Map.merge(sync_headers) |> Map.merge(sig_headers)
        :skip -> Map.merge(base_headers, sync_headers)
      end

    case Req.post(inbox_url, body: body, headers: Enum.to_list(headers)) do
      {:ok, %{status: status}} when status in 200..299 ->
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

  defp sign_request(nil, _inbox, _body), do: :skip

  defp sign_request(actor_uri, inbox_url, body) do
    case get_private_key_jwk(actor_uri) do
      nil ->
        :skip

      jwk ->
        key_id = "#{actor_uri}#main-key"

        case Client.request("ap.sign_delivery", %{
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
end
