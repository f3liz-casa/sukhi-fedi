# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.DbNatsListener do
  use GenServer
  require Logger
  alias SukhiFedi.{Accounts, Auth, Notes, Social, Repo, Schema, AP, Feeds, Articles, Media, Bookmarks, Moderation}
  import Ecto.Query

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, _sub} = Gnat.sub(:gnat, self(), "db.*")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:msg, %{topic: topic, reply_to: reply_to, body: body}}, state) do
    case Jason.decode(body) do
      {:ok, %{"request_id" => _req_id, "payload" => payload}} ->
        result = handle_topic(topic, payload)
        Gnat.pub(:gnat, reply_to, Jason.encode!(result))
      _ ->
        :ok
    end
    {:noreply, state}
  end

  defp handle_topic("db.account.create", payload) do
    case Accounts.create_account(payload) do
      {:ok, account} -> ok_resp(serialize_account(account))
      {:error, changeset} -> error_resp("Failed to create account: #{inspect(changeset.errors)}")
    end
  end

  defp handle_topic("db.account.update", %{"id" => id} = params) do
    account = Repo.get(Schema.Account, id)
    if account do
      case Accounts.update_profile(account, params) do
        {:ok, updated} -> ok_resp(serialize_account(updated))
        {:error, _} -> error_resp("Failed to update profile")
      end
    else
      error_resp("Account not found")
    end
  end

  defp handle_topic("db.auth.session", %{"username" => username, "password" => password}) do
    case Auth.authenticate(username, password) do
      {:ok, session} -> ok_resp(%{token: session.token})
      {:error, _} -> error_resp("Invalid credentials")
    end
  end

  defp handle_topic("db.auth.verify", %{"token" => token}) do
    case Auth.verify_session(token) do
      {:ok, account} -> ok_resp(serialize_account(account) |> Map.put(:is_admin, account.is_admin))
      {:error, _} -> error_resp("Unauthorized")
    end
  end

  defp handle_topic("db.note.create", %{"account_id" => account_id} = params) do
    attrs = %{
      "account_id" => account_id,
      "content" => params["text"],
      "visibility" => params["visibility"] || "public",
      "cw" => params["cw"],
      "mfm" => params["mfm"]
    }

    case Notes.create_note(attrs) do
      {:ok, note} -> ok_resp(serialize_note(note))
      {:error, changeset} -> error_resp("Failed to create note: #{inspect(changeset.errors)}")
    end
  end

  defp handle_topic("db.note.get", %{"id" => id}) do
    case Notes.get_note(id) do
      nil -> error_resp("Note not found")
      note -> ok_resp(serialize_note(note))
    end
  end

  defp handle_topic("db.note.delete", %{"id" => id, "account_id" => account_id}) do
    case Notes.get_note(id) do
      nil -> error_resp("Note not found")
      note ->
        if note.account_id == account_id do
          case Notes.delete_note(note) do
            {:ok, _} -> ok_resp(%{success: true})
            _ -> error_resp("Failed to delete note")
          end
        else
          error_resp("Forbidden")
        end
    end
  end

  defp handle_topic("db.note.like", %{"account_id" => account_id, "note_id" => note_id}) do
    case Notes.create_like(account_id, note_id) do
      {:ok, _} -> ok_resp(%{success: true})
      _ -> error_resp("Failed to like note")
    end
  end

  defp handle_topic("db.note.unlike", %{"account_id" => account_id, "note_id" => note_id}) do
    case Notes.delete_like(account_id, note_id) do
      :ok -> ok_resp(%{success: true})
      _ -> error_resp("Failed to unlike note")
    end
  end

  defp handle_topic("db.account.get", %{"username" => username}) do
    case Accounts.get_account_by_username(username) do
      nil -> error_resp("Account not found")
      account -> ok_resp(serialize_account(account))
    end
  end

  defp handle_topic("db.account.notes", %{"username" => username} = params) do
    case Accounts.get_account_by_username(username) do
      nil -> error_resp("Account not found")
      account ->
        opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
        result = Notes.list_notes_by_account(account.id, opts)
        ok_resp(result)
    end
  end

  # Social
  defp handle_topic("db.account.followers", %{"username" => username} = params) do
    case Accounts.get_account_by_username(username) do
      nil -> error_resp("Account not found")
      account ->
        opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
        ok_resp(Social.list_followers(account.id, opts))
    end
  end

  defp handle_topic("db.account.following", %{"username" => username} = params) do
    case Accounts.get_account_by_username(username) do
      nil -> error_resp("Account not found")
      account ->
        opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
        domain = Application.get_env(:sukhi_fedi, :domain)
        follower_uri = "https://#{domain}/users/#{account.username}"
        ok_resp(Social.list_following(follower_uri, opts))
    end
  end

  defp handle_topic("db.social.relationship.update", %{"account_id" => account_id, "target_id" => target_id} = params) do
    with account <- Repo.get(Schema.Account, account_id),
         target <- Repo.get(Schema.Account, target_id),
         true <- account != nil and target != nil do
      
      domain = Application.get_env(:sukhi_fedi, :domain)
      follower_uri = "https://#{domain}/users/#{account.username}"
      
      # Follow
      if Map.has_key?(params, "follow") do
        if params["follow"], do: Social.follow(follower_uri, target.id), else: Social.unfollow(follower_uri, target.id)
      end
      
      # Mute
      if Map.has_key?(params, "mute") do
        if params["mute"], do: Social.mute(account.id, target.id), else: Social.unmute(account.id, target.id)
      end
      
      # Block
      if Map.has_key?(params, "block") do
        if params["block"], do: Social.block(account.id, target.id), else: Social.unblock(account.id, target.id)
      end
      
      ok_resp(%{
        following: Social.following?(account.id, target.id),
        muting: Social.muting?(account.id, target.id),
        blocking: Social.blocking?(account.id, target.id)
      })
    else
      _ -> error_resp("Account or target not found")
    end
  end

  # Reactions
  defp handle_topic("db.note.reaction.add", %{"account_id" => account_id, "note_id" => note_id, "emoji" => emoji}) do
    with note when not is_nil(note) <- Repo.get(Schema.Note, note_id),
         {:ok, reaction} <- %Schema.Reaction{} |> Schema.Reaction.changeset(%{account_id: account_id, note_id: note_id, emoji: emoji}) |> Repo.insert() do
      
      AP.Client.request("reaction.create", %{actor_id: account_id, note_id: note_id, emoji: emoji})
      ok_resp(%{id: reaction.id, emoji: reaction.emoji, account_id: reaction.account_id, note_id: reaction.note_id})
    else
      nil -> error_resp("Note not found")
      {:error, _} -> error_resp("Failed to add reaction")
    end
  end

  defp handle_topic("db.note.reaction.remove", %{"account_id" => account_id, "note_id" => note_id, "emoji" => emoji}) do
    reaction = Schema.Reaction |> where([r], r.account_id == ^account_id and r.note_id == ^note_id and r.emoji == ^emoji) |> Repo.one()
    if reaction do
      Repo.delete(reaction)
      ok_resp(%{success: true})
    else
      error_resp("Reaction not found")
    end
  end

  defp handle_topic("db.note.reaction.list", %{"note_id" => note_id}) do
    reactions = Schema.Reaction |> where([r], r.note_id == ^note_id) |> Repo.all()
    ok_resp(%{reactions: Enum.map(reactions, fn r -> %{id: r.id, emoji: r.emoji, account_id: r.account_id, note_id: r.note_id} end)})
  end

  # Polls
  defp handle_topic("db.note.poll.vote", %{"account_id" => account_id, "note_id" => note_id, "choices" => choices}) do
    note = Repo.get(Schema.Note, note_id) |> Repo.preload(poll: :options)
    if note && note.poll do
      poll = note.poll
      max_idx = length(poll.options) - 1
      valid = is_list(choices) and Enum.all?(choices, fn c -> c >= 0 and c <= max_idx end)
      
      if valid do
        existing = Schema.PollVote |> where([v], v.account_id == ^account_id and v.poll_id == ^poll.id) |> Repo.all()
        if length(existing) > 0 and not poll.multiple do
          error_resp("Already voted")
        else
          Enum.each(choices, fn idx ->
            option = Enum.at(poll.options, idx)
            %Schema.PollVote{} |> Schema.PollVote.changeset(%{account_id: account_id, poll_id: poll.id, option_id: option.id}) |> Repo.insert()
          end)
          ok_resp(%{success: true})
        end
      else
        error_resp("Invalid choices")
      end
    else
      error_resp("Poll not found")
    end
  end

  # Feeds
  defp handle_topic("db.feed.get", %{"urn" => urn, "account_id" => account_id} = params) do
    opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
    case urn do
      "home" -> ok_resp(Feeds.home_feed(account_id, opts))
      "local" -> ok_resp(Feeds.local_feed(opts))
      "public" -> ok_resp(Feeds.public_feed(opts))
      _ -> error_resp("Feed not found")
    end
  end

  # Articles
  defp handle_topic("db.article.create", %{"account_id" => account_id} = params) do
    domain = Application.get_env(:sukhi_fedi, :domain)
    ap_id = "https://#{domain}/articles/#{:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)}"
    
    attrs = %{
      account_id: account_id,
      ap_id: ap_id,
      title: params["title"],
      content: params["content"],
      summary: params["summary"],
      published_at: DateTime.utc_now()
    }

    case Articles.create(attrs) do
      {:ok, article} -> ok_resp(serialize_article(article))
      _ -> error_resp("Failed to create article")
    end
  end

  defp handle_topic("db.article.list", params) do
    opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
    ok_resp(Articles.list(opts))
  end

  defp handle_topic("db.article.get", %{"id" => id}) do
    case Articles.get(id) do
      nil -> error_resp("Article not found")
      article -> ok_resp(serialize_article(article))
    end
  end

  # Media
  defp handle_topic("db.media.presigned", %{"account_id" => account_id, "filename" => filename, "mime_type" => mime_type, "size" => size}) do
    case Media.generate_upload_url(account_id, filename, mime_type, size) do
      {:ok, result} -> ok_resp(result)
      _ -> error_resp("Failed to generate upload URL")
    end
  end

  defp handle_topic("db.media.register", %{"account_id" => account_id} = params) do
    attrs = Map.put(params, "account_id", account_id)
    case Media.create_media(attrs) do
      {:ok, media} -> ok_resp(serialize_media(media))
      _ -> error_resp("Failed to register media")
    end
  end

  defp handle_topic("db.media.list", %{"account_id" => account_id} = params) do
    opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
    ok_resp(Media.list_by_account(account_id, opts))
  end

  # Emojis
  defp handle_topic("db.emoji.list", _) do
    emojis = Repo.all(Schema.Emoji)
    ok_resp(Enum.map(emojis, fn e -> %{shortcode: e.shortcode, url: e.url, category: e.category} end))
  end

  # Bookmarks
  defp handle_topic("db.bookmark.list", %{"account_id" => account_id} = params) do
    opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
    ok_resp(Bookmarks.list(account_id, opts))
  end

  defp handle_topic("db.bookmark.create", %{"account_id" => account_id, "note_id" => note_id}) do
    case Bookmarks.create(account_id, note_id) do
      {:ok, _} -> ok_resp(%{success: true})
      _ -> error_resp("Failed to create bookmark")
    end
  end

  defp handle_topic("db.bookmark.delete", %{"account_id" => account_id, "note_id" => note_id}) do
    Bookmarks.delete(account_id, note_id)
    ok_resp(%{success: true})
  end

  # Moderation & Admin
  defp handle_topic("db.moderation.report", %{"account_id" => account_id} = params) do
    attrs = Map.put(params, "account_id", account_id)
    case Moderation.create_report(attrs) do
      {:ok, report} -> ok_resp(%{id: report.id})
      _ -> error_resp("Failed to create report")
    end
  end

  defp handle_topic("db.admin.report.list", %{"status" => status}) do
    ok_resp(Moderation.list_reports(status || "open"))
  end

  defp handle_topic("db.admin.report.resolve", %{"id" => id, "admin_id" => admin_id}) do
    case Moderation.resolve_report(parse_int(id, 0), admin_id) do
      {:ok, _} -> ok_resp(%{success: true})
      _ -> error_resp("Failed to resolve report")
    end
  end

  defp handle_topic("db.admin.instance_block.create", %{"admin_id" => admin_id, "domain" => domain} = params) do
    severity = params["severity"] || "suspend"
    reason = params["reason"] || ""
    Moderation.block_instance(domain, severity, reason, admin_id)
    ok_resp(%{success: true})
  end

  defp handle_topic("db.admin.instance_block.delete", %{"domain" => domain}) do
    Moderation.unblock_instance(domain)
    ok_resp(%{success: true})
  end

  defp handle_topic("db.admin.instance_block.list", _) do
    ok_resp(Moderation.list_instance_blocks())
  end

  defp handle_topic("db.admin.account.suspend", %{"id" => id, "admin_id" => admin_id, "reason" => reason}) do
    case Moderation.suspend_account(parse_int(id, 0), admin_id, reason || "") do
      {:ok, _} -> ok_resp(%{success: true})
      _ -> error_resp("Failed to suspend account")
    end
  end

  defp handle_topic("db.admin.account.unsuspend", %{"id" => id}) do
    case Moderation.unsuspend_account(parse_int(id, 0)) do
      {:ok, _} -> ok_resp(%{success: true})
      _ -> error_resp("Failed to unsuspend account")
    end
  end

  defp handle_topic("db.admin.emoji.create", params) do
    case %Schema.Emoji{} |> Schema.Emoji.changeset(params) |> Repo.insert() do
      {:ok, emoji} -> ok_resp(%{shortcode: emoji.shortcode, url: emoji.url, category: emoji.category})
      _ -> error_resp("Failed to create emoji")
    end
  end

  defp handle_topic("db.admin.emoji.delete", %{"id" => id}) do
    emoji = Repo.get(Schema.Emoji, id)
    if emoji do
      Repo.delete(emoji)
      ok_resp(%{success: true})
    else
      error_resp("Emoji not found")
    end
  end

  defp handle_topic(topic, _) do
    Logger.warning("Unhandled NATS db topic: #{topic}")
    error_resp("Unknown topic")
  end

  defp ok_resp(data), do: %{ok: true, data: data}
  defp error_resp(error), do: %{ok: false, error: error}

  defp parse_int(nil, default), do: default
  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      _ -> default
    end
  end
  defp parse_int(int, _default) when is_integer(int), do: int
  defp parse_int(_, default), do: default

  defp serialize_account(account) do
    %{
      id: account.id,
      username: account.username,
      display_name: account.display_name,
      bio: account.bio,
      avatar_url: account.avatar_url,
      banner_url: account.banner_url,
      created_at: account.inserted_at
    }
  end

  defp serialize_article(article) do
    %{
      id: article.id,
      title: article.title,
      content: article.content,
      summary: article.summary,
      published_at: article.published_at,
      account_id: article.account_id
    }
  end

  defp serialize_media(media) do
    %{
      id: media.id,
      url: media.url,
      thumbnail_url: media.thumbnail_url,
      mime_type: media.mime_type,
      blurhash: media.blurhash,
      description: media.description,
      sensitive: media.sensitive
    }
  end

  defp serialize_note(note) do
    %{
      id: note.id,
      content: note.content,
      visibility: note.visibility,
      cw: note.cw,
      mfm: note.mfm,
      created_at: note.created_at,
      account_id: note.account_id
    }
  end
end
