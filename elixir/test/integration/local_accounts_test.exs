# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Integration.LocalAccountsTest do
  @moduledoc """
  Admin bootstrap + password change. Requires the test Postgres:

      docker compose -f docker-compose.test.yml up -d
      MIX_ENV=test mix ecto.migrate
      mix test --only integration
  """

  use SukhiFedi.IntegrationCase, async: false

  @moduletag :integration

  alias SukhiFedi.{Accounts, LocalAccounts}

  describe "create_admin/3" do
    test "mints a local admin account that can authenticate" do
      name = "admin_#{System.unique_integer([:positive])}"

      assert {:ok, account} = LocalAccounts.create_admin(name, "long-enough-pass")
      assert account.is_admin
      assert is_nil(account.domain)
      assert is_binary(account.password_hash)

      assert {:ok, signed_in} = LocalAccounts.authenticate(name, "long-enough-pass")
      assert signed_in.id == account.id
    end

    test "rejects a password under the 8-byte floor" do
      name = "admin_#{System.unique_integer([:positive])}"
      assert {:error, :password_too_short} = LocalAccounts.create_admin(name, "short")
    end

    test "rejects a duplicate username" do
      name = "admin_#{System.unique_integer([:positive])}"
      assert {:ok, _} = LocalAccounts.create_admin(name, "long-enough-pass")
      assert {:error, {:validation, errors}} = LocalAccounts.create_admin(name, "long-enough-pass")
      assert Map.has_key?(errors, :username)
    end
  end

  describe "change_password/3" do
    setup do
      name = "user_#{System.unique_integer([:positive])}"
      {:ok, account} = LocalAccounts.create_admin(name, "original-pass")
      %{account: account, name: name}
    end

    test "swaps the password when the current one matches", %{account: account, name: name} do
      assert {:ok, _} = LocalAccounts.change_password(account, "original-pass", "brand-new-pass")

      assert {:error, :invalid} = LocalAccounts.authenticate(name, "original-pass")
      assert {:ok, _} = LocalAccounts.authenticate(name, "brand-new-pass")
    end

    test "rejects a wrong current password", %{account: account, name: name} do
      assert {:error, :invalid_current} =
               LocalAccounts.change_password(account, "wrong-pass", "brand-new-pass")

      # unchanged — the original still works
      assert {:ok, _} = LocalAccounts.authenticate(name, "original-pass")
    end

    test "enforces the 8-byte floor on the new password", %{account: account} do
      assert {:error, :password_too_short} =
               LocalAccounts.change_password(account, "original-pass", "short")
    end

    test "revokes every session on success", %{account: account} do
      {:ok, token} = LocalAccounts.create_session(account)
      assert %{id: id} = Accounts.get_account_by_session_token(token)
      assert id == account.id

      assert {:ok, _} = LocalAccounts.change_password(account, "original-pass", "brand-new-pass")

      # the old session no longer resolves to an account
      assert is_nil(Accounts.get_account_by_session_token(token))
    end

    test "leaves sessions intact when the current password is wrong", %{account: account} do
      {:ok, token} = LocalAccounts.create_session(account)

      assert {:error, :invalid_current} =
               LocalAccounts.change_password(account, "wrong-pass", "brand-new-pass")

      assert %{id: id} = Accounts.get_account_by_session_token(token)
      assert id == account.id
    end
  end
end
