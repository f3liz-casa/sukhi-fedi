# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.AP.ActorJson do
  @moduledoc """
  Build the ActivityPub Person JSON-LD for a local account, and wrap it
  in an Update activity for distribution to followers when the actor's
  public state changes (notably right after we Accept a new Follow, so
  remote servers refresh their cached copy instead of showing stale
  follower counts).

  > ⚠️ Must stay shape-compatible with `SukhiDelivery.AP.ActorJson` on
  > the delivery node. Any key added on one side must be added on the
  > other in the same commit — see `SukhiFedi.AP.ActorJsonTest`.
  """

  alias SukhiFedi.Schema.Account

  @doc """
  Canonical local actor URI for an account or username. One place so
  string interpolation doesn't drift away from `build_person/1`.
  """
  @spec actor_uri(Account.t() | String.t()) :: String.t()
  def actor_uri(%Account{username: u}), do: actor_uri(u)

  def actor_uri(username) when is_binary(username) do
    "https://#{SukhiFedi.Config.domain!()}/users/#{username}"
  end

  @spec build_person(Account.t()) :: map()
  def build_person(%Account{} = account) do
    domain = SukhiFedi.Config.domain!()
    actor_uri = actor_uri(account)

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
      "manuallyApprovesFollowers" => account.locked || false,
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
    domain = SukhiFedi.Config.domain!()
    actor_uri = actor_uri(account)

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

  defp random_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
