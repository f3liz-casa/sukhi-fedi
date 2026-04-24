# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Outbox.Consumer do
  @moduledoc """
  Subscribes to `sns.outbox.>` and turns each event into one or more
  Oban delivery jobs.

  ## Subject coverage (PR5)

      sns.outbox.note.created       → Bun `note` translator   → fan out
      sns.outbox.note.deleted       → Bun `delete` translator → fan out
      sns.outbox.follow.requested   → Bun `follow` translator → followee inbox
      sns.outbox.follow.undone      → Bun `undo` (Follow)     → followee inbox
      sns.outbox.like.created       → Bun `like` translator   → note author + relays
      sns.outbox.like.undone        → Bun `undo` (Like)       → note author
      sns.outbox.announce.created   → Bun `announce`          → note author + followers
      sns.outbox.announce.undone    → Bun `undo` (Announce)   → note author + followers
      sns.outbox.add.created        → Bun `add` (featured)    → followers
      sns.outbox.remove.created     → Bun `remove` (featured) → followers

  Skipped today (TODO):
    * `sns.outbox.actor.updated` — needs Bun-side `Update(Actor)` wrapper
    * `sns.outbox.oauth.app_registered` — local-only, no federation

  ## Stream cleanup

  This consumer uses plain `Gnat.sub`, so messages are delivered as
  they're published but the JetStream OUTBOX stream is never ACKed
  and will grow forever. A durable JetStream consumer with explicit
  ACK is the proper next step; for the MVP we accept the growth and
  rely on the worker's `delivery_receipts` table for idempotency.

  ## Recipient inbox resolution

  Convention-based: `<actor_uri>/inbox`. Mastodon and most major
  fediverse software follow this. For implementations that publish
  a different inbox URL in their actor JSON, the gateway's
  `ActorFetcher` (not yet mirrored on the delivery side) would be
  the proper resolver — also tracked as a follow-up.
  """

  use GenServer
  require Logger

  import Ecto.Query

  alias SukhiDelivery.{Repo, Relays}
  alias SukhiDelivery.Delivery.{FedifyClient, Worker}
  alias SukhiDelivery.Schema.{Account, Follow}

  @subject_filter "sns.outbox.>"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    case :timer.send_interval(1_000, :ensure_subscription) do
      {:ok, _ref} -> {:ok, %{subscribed: false, sid: nil}}
      _ -> {:ok, %{subscribed: false, sid: nil}}
    end
  end

  @impl true
  def handle_info(:ensure_subscription, %{subscribed: true} = state), do: {:noreply, state}

  def handle_info(:ensure_subscription, state) do
    case Process.whereis(:gnat) do
      nil ->
        {:noreply, state}

      _pid ->
        case Gnat.sub(:gnat, self(), @subject_filter) do
          {:ok, sid} ->
            Logger.info("Outbox.Consumer subscribed to #{@subject_filter} (sid=#{sid})")
            {:noreply, %{state | subscribed: true, sid: sid}}

          {:error, reason} ->
            Logger.warning("Outbox.Consumer subscribe failed: #{inspect(reason)}")
            {:noreply, state}
        end
    end
  end

  def handle_info({:msg, %{topic: subject, body: body}}, state) do
    handle_event(subject, body)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("Outbox.Consumer ignoring: #{inspect(msg)}")
    {:noreply, state}
  end

  # ── event dispatch ───────────────────────────────────────────────────────

  @doc false
  def handle_event(subject, body) when is_binary(subject) and is_binary(body) do
    case Jason.decode(body) do
      {:ok, payload} when is_map(payload) ->
        try do
          dispatch(subject, payload)
        rescue
          e ->
            Logger.error(
              "Outbox.Consumer dispatch crash subject=#{subject}: " <>
                Exception.format(:error, e, __STACKTRACE__)
            )

            :crashed
        end

      _ ->
        Logger.warning("Outbox.Consumer: malformed JSON for #{subject}")
        :bad_json
    end
  end

  @doc false
  def dispatch("sns.outbox.note.created", p), do: handle_note_created(p)
  def dispatch("sns.outbox.note.deleted", p), do: handle_note_deleted(p)
  def dispatch("sns.outbox.follow.requested", p), do: handle_follow(p, :create)
  def dispatch("sns.outbox.follow.undone", p), do: handle_follow(p, :undo)
  def dispatch("sns.outbox.like.created", p), do: handle_like(p, :create)
  def dispatch("sns.outbox.like.undone", p), do: handle_like(p, :undo)
  def dispatch("sns.outbox.announce.created", p), do: handle_announce(p, :create)
  def dispatch("sns.outbox.announce.undone", p), do: handle_announce(p, :undo)
  def dispatch("sns.outbox.add.created", p), do: handle_collection_op(p, :add)
  def dispatch("sns.outbox.remove.created", p), do: handle_collection_op(p, :remove)

  def dispatch("sns.outbox.actor.updated", _p) do
    # TODO: Update(Actor) translator on Bun side
    :skipped
  end

  def dispatch("sns.outbox.oauth.app_registered", _p) do
    # local audit only — no federation
    :ignored
  end

  def dispatch(subject, _p) do
    Logger.debug("Outbox.Consumer: no handler for subject #{subject}")
    :no_handler
  end

  # ── handlers ─────────────────────────────────────────────────────────────

  defp handle_note_created(%{"account_id" => account_id} = p) do
    case actor_for(account_id) do
      nil ->
        :no_actor

      %{actor_uri: actor_uri} ->
        recipients = followers_inboxes(actor_uri) ++ relay_inboxes()
        note_id = p["note_id"]
        ap_id = note_ap_id(actor_uri, note_id)
        activity_id = "#{ap_id}/activity"

        translator_payload = %{
          actor: actor_uri,
          content: p["content"] || "",
          recipientInboxes: recipients,
          noteId: ap_id,
          activityId: activity_id
        }

        translate_and_fanout("note", translator_payload, actor_uri, activity_id, recipients,
          extract_note: true
        )
    end
  end

  defp handle_note_created(_), do: :missing_account

  defp handle_note_deleted(%{"account_id" => account_id, "ap_id" => ap_id} = _p) do
    case actor_for(account_id) do
      nil ->
        :no_actor

      %{actor_uri: actor_uri} ->
        recipients = followers_inboxes(actor_uri) ++ relay_inboxes()
        activity_id = "#{ap_id}#delete"

        translator_payload = %{
          actor: actor_uri,
          activityId: activity_id,
          objectId: ap_id,
          recipientInboxes: recipients
        }

        translate_and_fanout("delete", translator_payload, actor_uri, activity_id, recipients,
          extract: "delete"
        )
    end
  end

  defp handle_note_deleted(_), do: :missing_fields

  defp handle_follow(%{"follower_uri" => follower_uri, "followee_id" => followee_id} = p, mode) do
    case follower_uri_to_account(follower_uri) do
      nil ->
        :no_actor

      %{actor_uri: actor_uri} ->
        followee = Repo.get(Account, followee_id)

        if followee do
          domain = Application.get_env(:sukhi_delivery, :domain, "localhost:4000")
          followee_uri = "https://#{domain}/users/#{followee.username}"
          followee_inbox = "#{followee_uri}/inbox"

          activity_id =
            "https://#{domain}/follows/#{p["follow_id"]}#{if mode == :undo, do: "/undo", else: ""}"

          case mode do
            :create ->
              payload = %{actor: actor_uri, object: followee_uri, activityId: activity_id}
              translate_and_fanout("follow", payload, actor_uri, activity_id, [followee_inbox])

            :undo ->
              payload = %{
                actor: actor_uri,
                activityId: activity_id,
                recipientInboxes: [followee_inbox],
                inner: %{
                  type: "Follow",
                  id: "https://#{domain}/follows/#{p["follow_id"]}",
                  object: followee_uri
                }
              }

              translate_and_fanout("undo", payload, actor_uri, activity_id, [followee_inbox])
          end
        else
          :no_followee
        end
    end
  end

  defp handle_follow(_, _), do: :missing_fields

  defp handle_like(%{"account_id" => account_id, "note_ap_id" => note_ap_id} = p, mode) do
    case actor_for(account_id) do
      nil ->
        :no_actor

      %{actor_uri: actor_uri} ->
        recipients = note_author_inbox(note_ap_id) ++ relay_inboxes()
        domain = Application.get_env(:sukhi_delivery, :domain, "localhost:4000")

        activity_id =
          "https://#{domain}/likes/#{p["reaction_id"]}#{if mode == :undo, do: "/undo", else: ""}"

        case mode do
          :create ->
            payload = %{
              actor: actor_uri,
              object: note_ap_id,
              activityId: activity_id,
              recipientInboxes: recipients
            }

            translate_and_fanout("like", payload, actor_uri, activity_id, recipients)

          :undo ->
            payload = %{
              actor: actor_uri,
              activityId: activity_id,
              recipientInboxes: recipients,
              inner: %{
                type: "Like",
                id: "https://#{domain}/likes/#{p["reaction_id"]}",
                object: note_ap_id
              }
            }

            translate_and_fanout("undo", payload, actor_uri, activity_id, recipients)
        end
    end
  end

  defp handle_like(_, _), do: :missing_fields

  defp handle_announce(%{"account_id" => account_id, "note_ap_id" => note_ap_id} = p, mode) do
    case actor_for(account_id) do
      nil ->
        :no_actor

      %{actor_uri: actor_uri} ->
        recipients = followers_inboxes(actor_uri) ++ note_author_inbox(note_ap_id) ++ relay_inboxes()
        recipients = Enum.uniq(recipients)
        domain = Application.get_env(:sukhi_delivery, :domain, "localhost:4000")

        activity_id =
          "https://#{domain}/announces/#{p["boost_id"]}#{if mode == :undo, do: "/undo", else: ""}"

        case mode do
          :create ->
            payload = %{
              actor: actor_uri,
              object: note_ap_id,
              activityId: activity_id,
              recipientInboxes: recipients
            }

            translate_and_fanout("announce", payload, actor_uri, activity_id, recipients)

          :undo ->
            payload = %{
              actor: actor_uri,
              activityId: activity_id,
              recipientInboxes: recipients,
              inner: %{
                type: "Announce",
                id: "https://#{domain}/announces/#{p["boost_id"]}",
                object: note_ap_id
              }
            }

            translate_and_fanout("undo", payload, actor_uri, activity_id, recipients)
        end
    end
  end

  defp handle_announce(_, _), do: :missing_fields

  defp handle_collection_op(%{"account_id" => account_id, "note_ap_id" => note_ap_id} = p, op) do
    case actor_for(account_id) do
      nil ->
        :no_actor

      %{actor_uri: actor_uri} ->
        recipients = followers_inboxes(actor_uri) ++ relay_inboxes()
        domain = Application.get_env(:sukhi_delivery, :domain, "localhost:4000")
        activity_id = "https://#{domain}/#{op}/#{p["pinned_id"]}"
        target_uri = "#{actor_uri}/featured"

        payload = %{
          actor: actor_uri,
          objectUri: note_ap_id,
          targetUri: target_uri,
          activityId: activity_id,
          recipientInboxes: recipients
        }

        translate_and_fanout(Atom.to_string(op), payload, actor_uri, activity_id, recipients)
    end
  end

  defp handle_collection_op(_, _), do: :missing_fields

  # ── translation + fan-out ────────────────────────────────────────────────

  defp translate_and_fanout(object_type, payload, actor_uri, activity_id, inboxes, opts \\ []) do
    case FedifyClient.translate(object_type, payload) do
      {:ok, translator_result} ->
        body =
          extract_body(translator_result, object_type, opts)

        enqueue_jobs(body, actor_uri, activity_id, inboxes)

      {:error, reason} ->
        Logger.warning(
          "Outbox.Consumer: translate(#{object_type}) failed: #{inspect(reason)}"
        )

        :translate_failed
    end
  end

  # Bun translator results carry the payload under different keys per
  # type. Pick the right one — fall back to the whole result.
  defp extract_body(result, "note", _opts), do: Map.get(result, "note", result)
  defp extract_body(result, "delete", _opts), do: Map.get(result, "delete", result)
  defp extract_body(result, "follow", _opts), do: Map.get(result, "follow", result)
  defp extract_body(result, "accept", _opts), do: Map.get(result, "accept", result)
  defp extract_body(result, "announce", _opts), do: Map.get(result, "announce", result)
  defp extract_body(result, "like", _opts), do: Map.get(result, "like", result)
  defp extract_body(result, "undo", _opts), do: Map.get(result, "undo", result)
  defp extract_body(result, "add", _opts), do: Map.get(result, "activity", result)
  defp extract_body(result, "remove", _opts), do: Map.get(result, "activity", result)
  defp extract_body(result, _type, _opts), do: result

  defp enqueue_jobs(_body, _actor_uri, _activity_id, []), do: :no_recipients

  defp enqueue_jobs(body, actor_uri, activity_id, inboxes) do
    inboxes = Enum.uniq(inboxes)

    base = %{
      raw_json: body,
      actor_uri: actor_uri,
      activity_id: activity_id
    }

    changesets =
      Enum.map(inboxes, fn inbox -> base |> Map.put(:inbox_url, inbox) |> Worker.new() end)

    Oban.insert_all(SukhiDelivery.Oban, changesets)
    :ok
  end

  # ── DB helpers ───────────────────────────────────────────────────────────

  defp actor_for(account_id) when is_integer(account_id) or is_binary(account_id) do
    id = if is_binary(account_id), do: String.to_integer(account_id), else: account_id

    case Repo.get(Account, id) do
      nil ->
        nil

      %Account{username: u} ->
        domain = Application.get_env(:sukhi_delivery, :domain, "localhost:4000")
        %{actor_uri: "https://#{domain}/users/#{u}", username: u}
    end
  rescue
    _ -> nil
  end

  defp follower_uri_to_account(follower_uri) when is_binary(follower_uri) do
    domain = Application.get_env(:sukhi_delivery, :domain, "localhost:4000")
    expected_prefix = "https://#{domain}/users/"

    if String.starts_with?(follower_uri, expected_prefix) do
      username = String.replace_prefix(follower_uri, expected_prefix, "")

      case Repo.get_by(Account, username: username) do
        nil -> nil
        _ -> %{actor_uri: follower_uri, username: username}
      end
    else
      # Remote actor following us — they'd never be the source of an outbound activity.
      nil
    end
  end

  defp followers_inboxes(actor_uri) do
    domain = Application.get_env(:sukhi_delivery, :domain, "localhost:4000")
    expected_prefix = "https://#{domain}/users/"

    if String.starts_with?(actor_uri, expected_prefix) do
      username = String.replace_prefix(actor_uri, expected_prefix, "")

      case Repo.get_by(Account, username: username) do
        nil ->
          []

        %Account{id: id} ->
          from(f in Follow,
            where: f.followee_id == ^id and f.state == "accepted",
            select: f.follower_uri
          )
          |> Repo.all()
          |> Enum.map(&inbox_for_actor_uri/1)
          |> Enum.reject(&is_nil/1)
      end
    else
      []
    end
  end

  defp note_author_inbox(note_ap_id) when is_binary(note_ap_id) do
    # Convention: a note URI is `<actor_uri>/notes/<id>` or similar; the
    # author's actor URI is the parent path. This works for our own
    # notes and for Mastodon-shaped URIs. Best-effort.
    case URI.parse(note_ap_id) do
      %URI{scheme: scheme, host: host, path: path}
      when is_binary(scheme) and is_binary(host) and is_binary(path) ->
        # Strip the trailing `/notes/<id>` or `/statuses/<id>`
        actor_path =
          path
          |> String.split("/")
          |> Enum.reverse()
          |> Enum.drop(2)
          |> Enum.reverse()
          |> Enum.join("/")

        if actor_path == "" do
          []
        else
          ["#{scheme}://#{host}#{actor_path}/inbox"]
        end

      _ ->
        []
    end
  end

  defp note_author_inbox(_), do: []

  defp inbox_for_actor_uri(actor_uri) when is_binary(actor_uri) do
    "#{actor_uri}/inbox"
  end

  defp inbox_for_actor_uri(_), do: nil

  defp relay_inboxes, do: Relays.get_active_inbox_urls()

  defp note_ap_id(actor_uri, note_id) when is_binary(actor_uri) and not is_nil(note_id) do
    "#{actor_uri}/notes/#{note_id}"
  end

  defp note_ap_id(_, _), do: nil
end
