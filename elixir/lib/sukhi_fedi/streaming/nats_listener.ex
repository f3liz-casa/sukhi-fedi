# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Streaming.NatsListener do
  use GenServer
  alias SukhiFedi.Streaming.Registry

  @doc "Start the NATS listener"
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, _sub} = Gnat.sub(:gnat, self(), "stream.new_post")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:msg, %{topic: "stream.new_post", body: body}}, state) do
    case Jason.decode(body) do
      {:ok, %{"object" => object, "actor_id" => actor_id}} ->
        broadcast_to_feeds(object, actor_id)
      _ ->
        :ok
    end
    {:noreply, state}
  end

  defp broadcast_to_feeds(object, actor_id) do
    event = %{
      event: "update",
      payload: object
    }

    # Broadcast to local feed if local actor
    if local_actor?(actor_id) do
      Registry.broadcast(:local, event)
    end

    # Broadcast to home feeds of followers
    broadcast_to_followers(actor_id, event)
  end

  defp broadcast_to_followers(actor_id, event) do
    case extract_account_id(actor_id) do
      {:ok, account_id} ->
        followers = get_follower_account_ids(account_id)
        Enum.each(followers, fn follower_id ->
          Registry.broadcast(:home, event, follower_id)
        end)
      _ ->
        :ok
    end
  end

  defp local_actor?(actor_id) do
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
    String.starts_with?(actor_id, "https://#{domain}")
  end

  defp extract_account_id(actor_id) do
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
    case Regex.run(~r|https://#{Regex.escape(domain)}/users/(.+)|, actor_id) do
      [_, username] ->
        case SukhiFedi.Repo.get_by(SukhiFedi.Schema.Account, username: username) do
          nil -> :error
          account -> {:ok, account.id}
        end
      _ ->
        :error
    end
  end

  defp get_follower_account_ids(account_id) do
    import Ecto.Query
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")

    SukhiFedi.Repo.all(
      from f in SukhiFedi.Schema.Follow,
        where: f.followee_id == ^account_id and f.state == "accepted",
        where: fragment("? LIKE ?", f.follower_uri, ^"https://#{domain}%"),
        select: f.follower_uri
    )
    |> Enum.map(fn uri ->
      case extract_account_id(uri) do
        {:ok, id} -> id
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
