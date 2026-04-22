# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.AP.ActorJson do
  @moduledoc """
  Build the ActivityPub Person JSON-LD for a local account, and wrap it
  in an Update activity for distribution to followers when the actor's
  public state changes (notably right after we Accept a new Follow, so
  remote servers refresh their cached copy instead of showing stale
  follower counts).
  """

  alias SukhiFedi.Schema.Account

  @spec build_person(Account.t()) :: map()
  def build_person(%Account{} = account) do
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
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
      "publicKey" => %{
        "id" => "#{actor_uri}#main-key",
        "owner" => actor_uri,
        "publicKeyPem" => account.public_key_pem || ""
      }
    }
  end

  @spec build_update(Account.t()) :: map()
  def build_update(%Account{} = account) do
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
    actor_uri = "https://#{domain}/users/#{account.username}"

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
