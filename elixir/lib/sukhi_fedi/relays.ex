# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Relays do
  @moduledoc """
  Manages relay subscriptions for ActivityPub federation.
  A relay is a service that redistributes activities to/from the Fediverse.
  """

  import Ecto.Query
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Relay

  @doc "Subscribe to a relay by actor URI and inbox URI."
  def subscribe(actor_uri, inbox_uri, created_by_id \\ nil) do
    %Relay{}
    |> Relay.changeset(%{
      actor_uri: actor_uri,
      inbox_uri: inbox_uri,
      state: "pending",
      created_by_id: created_by_id
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  @doc "Mark a relay as accepted (called when we receive Accept(Follow) from relay)."
  def accept(actor_uri) do
    from(r in Relay, where: r.actor_uri == ^actor_uri)
    |> Repo.update_all(set: [state: "accepted"])
  end

  @doc "Unsubscribe from a relay."
  def unsubscribe(id) do
    case Repo.get(Relay, id) do
      nil -> {:error, :not_found}
      relay -> Repo.delete(relay)
    end
  end

  @doc "List all relays."
  def list do
    Repo.all(Relay)
  end

  @doc "Return inbox URLs of all accepted relays."
  def get_active_inbox_urls do
    from(r in Relay, where: r.state == "accepted", select: r.inbox_uri)
    |> Repo.all()
  end

  @doc "Find a relay by actor URI."
  def get_by_actor_uri(actor_uri) do
    Repo.get_by(Relay, actor_uri: actor_uri)
  end
end
