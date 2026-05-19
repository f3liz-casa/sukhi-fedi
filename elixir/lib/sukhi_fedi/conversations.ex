# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Conversations do
  @moduledoc """
  Mastodon conversations (DM thread) reads.

  A conversation here is a `conversation_ap_id` — every DM Note row
  carries one, and every participant has a row in
  `conversation_participants`. We don't track unread state yet
  (`unread` always `false`); when the writer side of DMs lands, that
  column should join here.

  `list/2` returns the most-recent note per conversation the viewer
  participates in, plus the *other* participants' accounts. The
  viewer is excluded from the `accounts` list to match Mastodon's
  semantics ("who else is in this thread").
  """

  import Ecto.Query

  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Account, ConversationParticipant, Note}

  @default_limit 20
  @max_limit 40

  @spec list(integer(), keyword() | map()) :: [map()]
  def list(viewer_id, opts \\ []) when is_integer(viewer_id) do
    opts = normalize(opts)
    limit = clamp(opts[:limit])

    convo_ids =
      Repo.all(
        from cp in ConversationParticipant,
          where: cp.account_id == ^viewer_id,
          select: cp.conversation_ap_id
      )

    if convo_ids == [] do
      []
    else
      last_notes = last_note_per_conversation(convo_ids, limit, opts)

      other_accounts = other_participants(convo_ids, viewer_id)

      Enum.map(last_notes, fn note ->
        cid = note.conversation_ap_id

        %{
          id: cid,
          unread: false,
          accounts: Map.get(other_accounts, cid, []),
          last_status: note
        }
      end)
    end
  end

  defp last_note_per_conversation(convo_ids, limit, opts) do
    # Take the newest note per conversation_ap_id, then page by note id.
    sub =
      from n in Note,
        where: n.conversation_ap_id in ^convo_ids,
        group_by: n.conversation_ap_id,
        select: %{cid: n.conversation_ap_id, max_id: max(n.id)}

    base =
      from n in Note,
        join: m in subquery(sub),
        on: m.max_id == n.id

    base
    |> maybe_max_id(opts[:max_id])
    |> maybe_since_id(opts[:since_id])
    |> order_by([n], desc: n.id)
    |> limit(^limit)
    |> Repo.all()
    |> Repo.preload([:account, :media, :tags])
  end

  defp other_participants(convo_ids, viewer_id) do
    rows =
      Repo.all(
        from cp in ConversationParticipant,
          join: a in Account,
          on: a.id == cp.account_id,
          where: cp.conversation_ap_id in ^convo_ids and cp.account_id != ^viewer_id,
          select: %{
            cid: cp.conversation_ap_id,
            account: %{
              id: a.id,
              username: a.username,
              display_name: a.display_name,
              summary: a.summary,
              domain: a.domain,
              actor_uri: a.actor_uri,
              avatar_url: a.avatar_url,
              banner_url: a.banner_url
            }
          }
      )

    Enum.group_by(rows, & &1.cid, & &1.account)
  end

  defp maybe_max_id(q, nil), do: q
  defp maybe_max_id(q, v), do: where(q, [n], n.id < ^to_int(v))

  defp maybe_since_id(q, nil), do: q
  defp maybe_since_id(q, v), do: where(q, [n], n.id > ^to_int(v))

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)

  defp clamp(n) when is_integer(n) and n > 0 and n <= @max_limit, do: n
  defp clamp(_), do: @default_limit

  defp normalize(opts) when is_list(opts), do: Map.new(opts)
  defp normalize(opts) when is_map(opts), do: opts
end
