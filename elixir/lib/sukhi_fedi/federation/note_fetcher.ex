# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Federation.NoteFetcher do
  @moduledoc """
  Fetch a remote `Note` (or `Article` / `Question`) and mirror it into
  the local `notes` table so timelines, replies, and AP-id resolution
  can treat it like any other row.

  Idempotent: a row already keyed by the same `ap_id` is returned
  as-is. The actor is upserted via `Federation.ActorFetcher` +
  `Federation.RemoteAccounts.upsert_from_actor_json/1`.

  This deliberately mirrors only enough fields for our Mastodon view to
  render a sensible Status — content, visibility from the audience,
  in_reply_to_ap_id. Reactions and engagement counts stay on the
  origin server.
  """

  require Logger

  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Account, Note}
  alias SukhiFedi.Federation.{ActorFetcher, RemoteAccounts}

  @public_ns "https://www.w3.org/ns/activitystreams#Public"
  @timeout_ms 10_000

  @spec fetch_and_mirror(String.t()) :: {:ok, Note.t()} | {:error, term()}
  def fetch_and_mirror(uri) when is_binary(uri) do
    case Repo.get_by(Note, ap_id: uri) do
      %Note{} = n ->
        {:ok, n}

      nil ->
        with {:ok, note_json} <- fetch_object(uri),
             {:ok, %Account{id: account_id}} <- resolve_attributed_to(note_json) do
          insert_note(note_json, account_id, uri)
        end
    end
  end

  defp fetch_object(uri) do
    headers = [
      {"accept", "application/activity+json, application/ld+json"},
      {"user-agent", "sukhi-fedi/0.1.0"}
    ]

    case Req.get(uri, headers: headers, receive_timeout: @timeout_ms) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, m} -> {:ok, m}
          {:error, reason} -> {:error, {:invalid_json, reason}}
        end

      {:ok, %{status: s}} ->
        {:error, {:http_status, s}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_attributed_to(note_json) do
    case attributed_uri(note_json) do
      nil ->
        {:error, :no_actor}

      uri ->
        case Repo.get_by(Account, actor_uri: uri) do
          %Account{} = a ->
            {:ok, a}

          nil ->
            with {:ok, actor_json} <- ActorFetcher.fetch(uri),
                 {:ok, %Account{} = a} <- RemoteAccounts.upsert_from_actor_json(actor_json) do
              {:ok, a}
            end
        end
    end
  end

  defp attributed_uri(%{"attributedTo" => v}), do: extract(v)
  defp attributed_uri(%{"actor" => v}), do: extract(v)
  defp attributed_uri(_), do: nil

  defp extract(v) when is_binary(v), do: v
  defp extract(%{"id" => id}) when is_binary(id), do: id
  defp extract(_), do: nil

  # Misskey/forks signal a quote-note with one of these top-level
  # fields; mirror it so the link survives the fetch.
  defp quote_uri(note) do
    extract(note["quoteUrl"]) || extract(note["quoteUri"]) || extract(note["_misskey_quote"])
  end

  defp insert_note(note_json, account_id, uri) do
    attrs = %{
      "account_id" => account_id,
      "content" => note_json["content"] || "",
      "ap_id" => uri,
      "visibility" => visibility_from(note_json),
      "in_reply_to_ap_id" => extract(note_json["inReplyTo"]),
      "quote_of_ap_id" => quote_uri(note_json)
    }

    %Note{}
    |> Note.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: :ap_id)
    |> case do
      {:ok, %Note{id: nil}} ->
        # on_conflict :nothing on a hit returns the struct without an id;
        # re-fetch.
        {:ok, Repo.get_by(Note, ap_id: uri)}

      {:ok, %Note{} = n} ->
        {:ok, n}

      {:error, _} = err ->
        err
    end
  end

  defp visibility_from(note) do
    to = list(note["to"])
    cc = list(note["cc"])
    cond do
      Enum.any?(to, &public?/1) -> "public"
      Enum.any?(cc, &public?/1) -> "unlisted"
      Enum.any?(to ++ cc, &String.ends_with?(&1 || "", "/followers")) -> "followers"
      true -> "direct"
    end
  end

  defp list(v) when is_list(v), do: v
  defp list(v) when is_binary(v), do: [v]
  defp list(_), do: []

  defp public?(v) when is_binary(v), do: v == @public_ns or v == "Public"
  defp public?(_), do: false
end
