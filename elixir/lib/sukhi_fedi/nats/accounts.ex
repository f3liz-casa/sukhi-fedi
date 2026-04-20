# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Nats.Accounts do
  @moduledoc """
  `db.account.*`, `db.auth.*`, `db.social.*` topic handlers.
  """

  import SukhiFedi.Nats.Helpers

  alias SukhiFedi.{Accounts, Auth, Notes, Social, Repo}
  alias SukhiFedi.Schema.Account

  def handle("db.account.create", payload) do
    case Accounts.create_account(payload) do
      {:ok, account} ->
        ok_resp(serialize_account(account))

      {:error, changeset} ->
        error_resp("Failed to create account: #{inspect(changeset.errors)}")
    end
  end

  def handle("db.account.update", %{"id" => id} = params) do
    case Repo.get(Account, id) do
      nil ->
        error_resp("Account not found")

      account ->
        case Accounts.update_profile(account, params) do
          {:ok, updated} -> ok_resp(serialize_account(updated))
          {:error, _} -> error_resp("Failed to update profile")
        end
    end
  end

  def handle("db.auth.session", %{"username" => username, "password" => password}) do
    case Auth.authenticate(username, password) do
      {:ok, session} -> ok_resp(%{token: session.token})
      {:error, _} -> error_resp("Invalid credentials")
    end
  end

  def handle("db.auth.verify", %{"token" => token}) do
    case Auth.verify_session(token) do
      {:ok, account} ->
        ok_resp(serialize_account(account) |> Map.put(:is_admin, account.is_admin))

      {:error, _} ->
        error_resp("Unauthorized")
    end
  end

  def handle("db.account.get", %{"username" => username}) do
    case Accounts.get_account_by_username(username) do
      nil -> error_resp("Account not found")
      account -> ok_resp(serialize_account(account))
    end
  end

  def handle("db.account.notes", %{"username" => username} = params) do
    case Accounts.get_account_by_username(username) do
      nil ->
        error_resp("Account not found")

      account ->
        opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
        ok_resp(Notes.list_notes_by_account(account.id, opts))
    end
  end

  def handle("db.account.followers", %{"username" => username} = params) do
    case Accounts.get_account_by_username(username) do
      nil ->
        error_resp("Account not found")

      account ->
        opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
        ok_resp(Social.list_followers(account.id, opts))
    end
  end

  def handle("db.account.following", %{"username" => username} = params) do
    case Accounts.get_account_by_username(username) do
      nil ->
        error_resp("Account not found")

      account ->
        opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
        domain = Application.get_env(:sukhi_fedi, :domain)
        follower_uri = "https://#{domain}/users/#{account.username}"
        ok_resp(Social.list_following(follower_uri, opts))
    end
  end

  def handle("db.social.relationship.update", %{"account_id" => account_id, "target_id" => target_id} = params) do
    with account <- Repo.get(Account, account_id),
         target <- Repo.get(Account, target_id),
         true <- account != nil and target != nil do
      domain = Application.get_env(:sukhi_fedi, :domain)
      follower_uri = "https://#{domain}/users/#{account.username}"

      if Map.has_key?(params, "follow") do
        if params["follow"],
          do: Social.follow(follower_uri, target.id),
          else: Social.unfollow(follower_uri, target.id)
      end

      if Map.has_key?(params, "mute") do
        if params["mute"],
          do: Social.mute(account.id, target.id),
          else: Social.unmute(account.id, target.id)
      end

      if Map.has_key?(params, "block") do
        if params["block"],
          do: Social.block(account.id, target.id),
          else: Social.unblock(account.id, target.id)
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

  def handle(_, _), do: :unhandled
end
