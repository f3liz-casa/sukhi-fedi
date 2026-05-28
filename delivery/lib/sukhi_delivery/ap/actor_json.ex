# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.AP.ActorJson do
  @moduledoc """
  Build Person / Update(Person) JSON-LD for a local account.

  Mirrors `SukhiFedi.AP.ActorJson` on the gateway. Lives here because
  `Outbox.Consumer` runs on the delivery node and needs to fan out
  Update(Actor) without a round-trip back to the gateway.
  """

  alias SukhiDelivery.Schema.Account

  @spec build_person(Account.t()) :: map()
  def build_person(%Account{} = account) do
    domain = SukhiDelivery.Config.domain!()
    actor_uri = "https://#{domain}/users/#{account.username}"

    %{
      "@context" => [
        "https://www.w3.org/ns/activitystreams",
        "https://w3id.org/security/v1",
        %{
          "featured" => %{"@id" => "toot:featured", "@type" => "@id"},
          "toot" => "http://joinmastodon.org/ns#"
        }
      ],
      "id" => actor_uri,
      "type" => "Person",
      "preferredUsername" => account.username,
      "name" => account.display_name || account.username,
      "summary" => account.summary || "",
      "inbox" => "#{actor_uri}/inbox",
      "outbox" => "#{actor_uri}/outbox",
      "followers" => "#{actor_uri}/followers",
      "following" => "#{actor_uri}/following",
      "featured" => "#{actor_uri}/featured",
      "endpoints" => %{"sharedInbox" => "https://#{domain}/inbox"},
      "publicKey" => %{
        "id" => "#{actor_uri}#main-key",
        "owner" => actor_uri,
        "publicKeyPem" => account.public_key_pem || ""
      }
    }
    |> maybe_put_image("icon", account.avatar_url)
    |> maybe_put_image("image", account.banner_url)
  end

  defp maybe_put_image(map, _key, nil), do: map
  defp maybe_put_image(map, _key, ""), do: map

  defp maybe_put_image(map, key, url) do
    Map.put(map, key, %{
      "type" => "Image",
      "mediaType" => media_type_for(url),
      "url" => url
    })
  end

  defp media_type_for(url) do
    case url |> Path.extname() |> String.downcase() do
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _ -> "image/jpeg"
    end
  end

  @spec build_update(Account.t()) :: map()
  def build_update(%Account{} = account) do
    actor_uri = actor_uri(account)
    domain = SukhiDelivery.Config.domain!()

    %{
      "@context" => [
        "https://www.w3.org/ns/activitystreams",
        "https://w3id.org/security/v1"
      ],
      "id" => "https://#{domain}/activities/update/#{random_id()}",
      "type" => "Update",
      "actor" => actor_uri,
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => ["#{actor_uri}/followers"],
      "object" => build_person(account)
    }
  end

  defp actor_uri(%Account{username: u}) do
    domain = SukhiDelivery.Config.domain!()
    "https://#{domain}/users/#{u}"
  end

  defp random_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
