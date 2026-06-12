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

  describe "create/1 (signup)" do
    setup do
      issuer = "inv_#{System.unique_integer([:positive])}"
      {:ok, issuer} = LocalAccounts.create_admin(issuer, "long-enough-pass")
      {:ok, invite} = SukhiFedi.InviteCodes.issue(issuer.id)
      %{invite: invite.code}
    end

    defp signup_attrs(invite, overrides) do
      n = System.unique_integer([:positive])

      Map.merge(
        %{
          "username" => "signup_#{n}",
          "password" => "long-enough-pass",
          "email" => "signup_#{n}@example.test",
          "invite_code" => invite
        },
        overrides
      )
    end

    test "stores the email normalized and unverified", %{invite: invite} do
      attrs = signup_attrs(invite, %{"email" => "  Mixed.Case@Example.TEST "})

      assert {:ok, account} = LocalAccounts.create(attrs)
      assert account.email == "mixed.case@example.test"
      assert is_nil(account.email_verified_at)
    end

    test "email is required regardless of anything else", %{invite: invite} do
      attrs = signup_attrs(invite, %{"email" => nil})
      assert {:error, {:validation, %{email: [msg]}}} = LocalAccounts.create(attrs)
      assert msg =~ "入れて"

      attrs = signup_attrs(invite, %{"email" => "   "})
      assert {:error, {:validation, %{email: _}}} = LocalAccounts.create(attrs)
    end

    test "a malformed email is refused", %{invite: invite} do
      attrs = signup_attrs(invite, %{"email" => "not-an-email"})
      assert {:error, {:validation, %{email: [msg]}}} = LocalAccounts.create(attrs)
      assert msg =~ "メールアドレス"
    end

    test "two signups may carry the same (unverified) address", %{invite: invite} do
      issuer = "inv2_#{System.unique_integer([:positive])}"
      {:ok, issuer} = LocalAccounts.create_admin(issuer, "long-enough-pass")
      {:ok, invite2} = SukhiFedi.InviteCodes.issue(issuer.id)

      shared = "shared_#{System.unique_integer([:positive])}@example.test"
      assert {:ok, _} = LocalAccounts.create(signup_attrs(invite, %{"email" => shared}))
      assert {:ok, _} = LocalAccounts.create(signup_attrs(invite2.code, %{"email" => shared}))
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

    test "revokes the account's OAuth tokens too (C5)", %{account: account} do
      # Insert the app row directly (no register_app side effects) — we only
      # need a valid app_id FK for the token.
      app =
        SukhiFedi.Repo.insert!(%SukhiFedi.Schema.OauthApp{
          client_id: "c_#{System.unique_integer([:positive])}",
          client_secret_hash: "x",
          name: "pwchg",
          redirect_uri: "urn:ietf:wg:oauth:2.0:oob",
          scopes: "read"
        })

      {:ok, tok} =
        %SukhiFedi.Schema.OauthAccessToken{}
        |> SukhiFedi.Schema.OauthAccessToken.changeset(%{
          token_hash: "th_#{System.unique_integer([:positive])}",
          scopes: "read",
          app_id: app.id,
          account_id: account.id
        })
        |> SukhiFedi.Repo.insert()

      assert is_nil(tok.revoked_at)

      assert {:ok, _} = LocalAccounts.change_password(account, "original-pass", "brand-new-pass")

      assert SukhiFedi.Repo.get(SukhiFedi.Schema.OauthAccessToken, tok.id).revoked_at != nil
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
