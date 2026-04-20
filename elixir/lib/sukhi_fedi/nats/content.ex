# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Nats.Content do
  @moduledoc """
  `db.article.*`, `db.media.*`, `db.emoji.*`, `db.feed.*` topic handlers.
  """

  import SukhiFedi.Nats.Helpers

  alias SukhiFedi.{Repo, Schema}
  alias SukhiFedi.Addons.{Articles, Feeds, Media}

  # ── Feeds ──────────────────────────────────────────────────────────────────

  def handle("db.feed.get", %{"urn" => urn, "account_id" => account_id} = params) do
    opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]

    case urn do
      "home" -> ok_resp(Feeds.home_feed(account_id, opts))
      "local" -> ok_resp(Feeds.local_feed(opts))
      "public" -> ok_resp(Feeds.public_feed(opts))
      _ -> error_resp("Feed not found")
    end
  end

  # ── Articles ───────────────────────────────────────────────────────────────

  def handle("db.article.create", %{"account_id" => account_id} = params) do
    domain = Application.get_env(:sukhi_fedi, :domain)

    ap_id =
      "https://#{domain}/articles/#{:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)}"

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

  def handle("db.article.list", params) do
    opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
    ok_resp(Articles.list(opts))
  end

  def handle("db.article.get", %{"id" => id}) do
    case Articles.get(id) do
      nil -> error_resp("Article not found")
      article -> ok_resp(serialize_article(article))
    end
  end

  # ── Media ──────────────────────────────────────────────────────────────────

  def handle("db.media.presigned", %{"account_id" => account_id, "filename" => filename, "mime_type" => mime_type, "size" => size}) do
    case Media.generate_upload_url(account_id, filename, mime_type, size) do
      {:ok, result} -> ok_resp(result)
      _ -> error_resp("Failed to generate upload URL")
    end
  end

  def handle("db.media.register", %{"account_id" => account_id} = params) do
    attrs = Map.put(params, "account_id", account_id)

    case Media.create_media(attrs) do
      {:ok, media} -> ok_resp(serialize_media(media))
      _ -> error_resp("Failed to register media")
    end
  end

  def handle("db.media.list", %{"account_id" => account_id} = params) do
    opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
    ok_resp(Media.list_by_account(account_id, opts))
  end

  # ── Emoji ──────────────────────────────────────────────────────────────────

  def handle("db.emoji.list", _) do
    emojis = Repo.all(Schema.Emoji)

    ok_resp(
      Enum.map(emojis, fn e ->
        %{shortcode: e.shortcode, url: e.url, category: e.category}
      end)
    )
  end

  def handle(_, _), do: :unhandled
end
