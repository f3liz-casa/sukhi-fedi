# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Nats.Admin do
  @moduledoc """
  `db.moderation.*`, `db.admin.*` topic handlers — reports, instance
  blocks, account suspension, emoji admin, relay subscription.
  """

  import SukhiFedi.Nats.Helpers

  alias SukhiFedi.{Relays, Repo, Schema}
  alias SukhiFedi.Addons.Moderation
  alias SukhiFedi.Delivery.FedifyClient

  # ── Moderation / Reports ───────────────────────────────────────────────────

  def handle("db.moderation.report", %{"account_id" => account_id} = params) do
    attrs = Map.put(params, "account_id", account_id)

    case Moderation.create_report(attrs) do
      {:ok, report} -> ok_resp(%{id: report.id})
      _ -> error_resp("Failed to create report")
    end
  end

  def handle("db.admin.report.list", %{"status" => status}) do
    ok_resp(Moderation.list_reports(status || "open"))
  end

  def handle("db.admin.report.resolve", %{"id" => id, "admin_id" => admin_id}) do
    case Moderation.resolve_report(parse_int(id, 0), admin_id) do
      {:ok, _} -> ok_resp(%{success: true})
      _ -> error_resp("Failed to resolve report")
    end
  end

  # ── Instance blocks ────────────────────────────────────────────────────────

  def handle("db.admin.instance_block.create", %{"admin_id" => admin_id, "domain" => domain} = params) do
    severity = params["severity"] || "suspend"
    reason = params["reason"] || ""
    Moderation.block_instance(domain, severity, reason, admin_id)
    ok_resp(%{success: true})
  end

  def handle("db.admin.instance_block.delete", %{"domain" => domain}) do
    Moderation.unblock_instance(domain)
    ok_resp(%{success: true})
  end

  def handle("db.admin.instance_block.list", _) do
    ok_resp(Moderation.list_instance_blocks())
  end

  # ── Account suspension ─────────────────────────────────────────────────────

  def handle("db.admin.account.suspend", %{"id" => id, "admin_id" => admin_id, "reason" => reason}) do
    case Moderation.suspend_account(parse_int(id, 0), admin_id, reason || "") do
      {:ok, _} -> ok_resp(%{success: true})
      _ -> error_resp("Failed to suspend account")
    end
  end

  def handle("db.admin.account.unsuspend", %{"id" => id}) do
    case Moderation.unsuspend_account(parse_int(id, 0)) do
      {:ok, _} -> ok_resp(%{success: true})
      _ -> error_resp("Failed to unsuspend account")
    end
  end

  # ── Emoji admin ────────────────────────────────────────────────────────────

  def handle("db.admin.emoji.create", params) do
    case %Schema.Emoji{} |> Schema.Emoji.changeset(params) |> Repo.insert() do
      {:ok, emoji} ->
        ok_resp(%{shortcode: emoji.shortcode, url: emoji.url, category: emoji.category})

      _ ->
        error_resp("Failed to create emoji")
    end
  end

  def handle("db.admin.emoji.delete", %{"id" => id}) do
    case Repo.get(Schema.Emoji, id) do
      nil ->
        error_resp("Emoji not found")

      emoji ->
        Repo.delete(emoji)
        ok_resp(%{success: true})
    end
  end

  # ── Relay Management ───────────────────────────────────────────────────────

  def handle("db.admin.relay.subscribe", %{"actor_uri" => actor_uri, "admin_id" => admin_id} = params) do
    inbox_uri = params["inbox_uri"] || derive_inbox_uri(actor_uri)

    case Relays.subscribe(actor_uri, inbox_uri, admin_id) do
      {:ok, relay} ->
        domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
        instance_actor = "https://#{domain}/actor"

        follow_id =
          "https://#{domain}/follows/#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"

        FedifyClient.translate("follow", %{
          actor: instance_actor,
          object: actor_uri,
          followId: follow_id,
          recipientInboxes: [inbox_uri]
        })

        ok_resp(%{id: relay.id, actor_uri: relay.actor_uri, state: relay.state})

      {:error, _} ->
        error_resp("Failed to subscribe to relay")
    end
  end

  def handle("db.admin.relay.unsubscribe", %{"id" => id, "admin_id" => _admin_id}) do
    case Relays.unsubscribe(parse_int(id, 0)) do
      {:ok, _} -> ok_resp(%{success: true})
      {:error, :not_found} -> error_resp("Relay not found")
      _ -> error_resp("Failed to unsubscribe")
    end
  end

  def handle("db.admin.relay.list", _) do
    relays =
      Relays.list()
      |> Enum.map(fn r ->
        %{id: r.id, actor_uri: r.actor_uri, inbox_uri: r.inbox_uri, state: r.state}
      end)

    ok_resp(%{relays: relays})
  end

  def handle(_, _), do: :unhandled
end
