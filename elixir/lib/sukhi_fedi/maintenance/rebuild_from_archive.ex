# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Maintenance.RebuildFromArchive do
  @moduledoc """
  Backfill existing remote notes from the raw inbound archive in rustfs.

  Two fields were historically dropped on ingest and only fixed going
  forward: the content warning (AP `summary` → `cw`, fixed v0.2.4) and
  the publish time (AP `published` → `created_at`, fixed v0.2.2). Notes
  mirrored before those fixes still show no spoiler and a fetch-time
  date. The bytes the remote signed are kept verbatim in the `inbound`
  bucket (`SukhiFedi.Federation.InboundArchive`), so we can recover the
  originals without hitting the network — the archive is the system of
  record, and replaying it is exactly what it's for.

  The `inbound_events` index keys on the *activity* id, not the inner
  note's id, so we walk every archived `Create` / `Update`, decompress
  the body, pull the embedded note, and match it to a local row by
  `ap_id`. We only ever set `cw`, `created_at`, and `emojis`, and only
  when the archive has a value that differs — content and everything else
  were captured correctly at ingest and are left untouched. The numeric
  id stays put, so reactions / boosts / threading are unaffected.

  Run on the live gateway (needs its Repo + rustfs credentials):

      bin/sukhi_fedi rpc 'SukhiFedi.Maintenance.RebuildFromArchive.run(:dry_run)'
      bin/sukhi_fedi rpc 'SukhiFedi.Maintenance.RebuildFromArchive.run(:execute)'
  """

  import Ecto.Query
  require Logger

  alias SukhiFedi.AP.{Emojis, Published}
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{InboundEvent, Note}

  @note_activities ~w(Create Update)

  @spec run(:dry_run | :execute) :: map()
  def run(mode \\ :dry_run) do
    events = note_events()
    Logger.info("rebuild_from_archive: #{length(events)} Create/Update event(s), mode=#{mode}")

    results =
      Enum.map(events, fn ev ->
        case fetch_inner_note(ev) do
          {:ok, note} ->
            rebuild_note(note, mode)

          {:error, reason} ->
            Logger.warning("  skip #{ev.object_key}: #{inspect(reason)}")
            :error
        end
      end)

    summary = tally(results)
    Logger.info("rebuild_from_archive done: #{inspect(summary)}")
    Map.put(summary, :mode, mode)
  end

  defp note_events do
    from(e in InboundEvent,
      where: e.activity_type in @note_activities,
      order_by: e.received_at
    )
    |> Repo.all()
  end

  # Download + decompress + decode one archived activity, returning its
  # embedded note object.
  defp fetch_inner_note(%InboundEvent{object_key: key}) do
    with {:ok, body} <- download(key),
         {:ok, json} <- Jason.decode(body),
         %{} = note <- inner_note(json) do
      {:ok, note}
    else
      nil -> {:error, :no_inline_note}
      {:error, _} = err -> err
    end
  end

  defp download(key) do
    bucket = Application.get_env(:sukhi_fedi, :s3, [])[:inbound_bucket] || "inbound"

    case bucket |> ExAws.S3.get_object(key) |> ExAws.request() do
      {:ok, %{body: compressed}} ->
        case :ezstd.decompress(compressed) do
          bin when is_binary(bin) -> {:ok, bin}
          other -> {:error, {:zstd, other}}
        end

      {:error, reason} ->
        {:error, {:s3, reason}}
    end
  end

  # A Create/Update carries the note inline as `object`. A bare-id object
  # (just a URI) can't be reconstructed from, so it's skipped.
  defp inner_note(%{"object" => %{} = obj}), do: obj
  defp inner_note(_), do: nil

  @doc """
  Backfill the local note matching `note["id"]` from an archived note
  object. Sets `cw` / `created_at` only when the archive has a value that
  differs from what's stored. Exposed for testing.
  """
  @spec rebuild_note(map(), :dry_run | :execute) :: atom()
  def rebuild_note(%{"id" => ap_id} = note, mode) when is_binary(ap_id) do
    case Repo.get_by(Note, ap_id: ap_id) do
      %Note{} = existing ->
        changes = note_changes(note, existing)

        cond do
          changes == %{} -> :unchanged
          mode == :dry_run -> :would_update
          true -> existing |> Ecto.Changeset.change(changes) |> Repo.update!() && :updated
        end

      nil ->
        :no_local_note
    end
  end

  def rebuild_note(_, _), do: :no_object_id

  defp note_changes(note, %Note{} = existing) do
    %{}
    |> put_new_value(:cw, content_warning(note), existing.cw)
    |> put_new_value(:created_at, Published.at(note), existing.created_at)
    |> put_new_value(:emojis, Emojis.from_tag(note["tag"]), existing.emojis)
  end

  # Only a non-empty archive value that differs is a change — we never
  # clear a field the archive happens to omit.
  defp put_new_value(changes, _key, nil, _old), do: changes
  defp put_new_value(changes, _key, [], _old), do: changes
  defp put_new_value(changes, _key, value, value), do: changes
  defp put_new_value(changes, key, value, _old), do: Map.put(changes, key, value)

  defp content_warning(%{"summary" => s}) when is_binary(s) and s != "", do: s
  defp content_warning(_), do: nil

  defp tally(results) do
    Enum.reduce(results, %{}, fn r, acc -> Map.update(acc, r, 1, &(&1 + 1)) end)
  end
end
