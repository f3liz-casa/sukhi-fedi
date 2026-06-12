# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Auth.EmailAuth do
  @moduledoc """
  Email-based proofs: verifying that an address belongs to the account
  (`purpose: "verify"`), and logging in with a code sent to a verified
  address (`purpose: "login"`).

  One shape for both: a 6-digit code, hashed at rest, 10 minutes to
  live, 5 guesses, one live code per (account, purpose) — requesting
  again replaces the old one. Sending is rate-limited per address
  before any account lookup happens, so the limiter can't be used to
  probe which addresses exist; `request_login_code/1` answers `:ok`
  for unknown addresses for the same reason.

  Email login is only for *verified* addresses — `email_verified_at`
  is the single gate (`login_account_by_email/1`).
  """

  import Ecto.Query

  alias Ecto.Multi
  alias SukhiFedi.{Mailer, Repo}
  alias SukhiFedi.Schema.{Account, EmailCode}

  @code_ttl_seconds 600
  @max_attempts 5
  # 3 sends per address per 15 minutes; 10 per account per hour.
  @send_per_email {3, 15 * 60 * 1000}
  @send_per_account {10, 60 * 60 * 1000}

  # ── verify flow (signed-in account claims an address) ────────────────────

  @spec request_verification(Account.t(), String.t()) ::
          :ok | {:error, :invalid_email | :email_taken | :rate_limited | :send_failed}
  def request_verification(%Account{} = account, email) do
    with {:ok, norm} <- normalize_email(email),
         :ok <- check_rate(norm, account.id),
         :ok <- check_available(norm, account.id) do
      issue(account, "verify", norm)
    end
  end

  @doc """
  Check the code and land the address on the account: `email` +
  `email_verified_at` in one transaction with the code row's removal.
  A lost race on the unique index surfaces as `:email_taken` and the
  code stays usable, so retrying is honest.
  """
  @spec confirm_verification(Account.t(), String.t()) ::
          {:ok, Account.t()}
          | {:error, :invalid_code | :expired | :too_many_attempts | :email_taken}
  def confirm_verification(%Account{id: account_id} = account, code) do
    with {:ok, row} <- match_code(account_id, "verify", code) do
      now = utc_now()

      changeset =
        account
        |> Ecto.Changeset.cast(%{email: row.email}, [:email])
        |> Account.validate_email()
        |> Ecto.Changeset.put_change(:email_verified_at, now)

      Multi.new()
      |> Multi.update(:account, changeset)
      |> Multi.delete(:code, row)
      |> Repo.transaction()
      |> case do
        {:ok, %{account: updated}} -> {:ok, updated}
        {:error, :account, %Ecto.Changeset{errors: errors}, _} -> verify_update_error(errors)
        {:error, _step, _reason, _} -> {:error, :invalid_code}
      end
    end
  end

  defp verify_update_error(errors) do
    case Keyword.get(errors, :email) do
      {_, opts} ->
        if opts[:constraint] == :unique,
          do: {:error, :email_taken},
          else: {:error, :invalid_code}

      nil ->
        {:error, :invalid_code}
    end
  end

  # ── login flow (nobody is signed in) ─────────────────────────────────────

  @doc """
  Mail a login code if a local account owns this verified address.
  Unknown addresses get the same `:ok` — the mailbox knows, we don't
  tell. `:rate_limited` is keyed on the address alone (before lookup),
  so it leaks nothing either.
  """
  @spec request_login_code(String.t()) :: :ok | {:error, :invalid_email | :rate_limited}
  def request_login_code(email) do
    with {:ok, norm} <- normalize_email(email),
         :ok <- check_rate(norm, nil) do
      case login_account_by_email(norm) do
        %Account{} = account ->
          # A failed send degrades to "the mail didn't come" — same as
          # an unknown address, which is exactly the public behaviour.
          _ = issue(account, "login", norm)
          :ok

        nil ->
          :ok
      end
    end
  end

  @spec confirm_login(String.t(), String.t()) ::
          {:ok, Account.t()}
          | {:error, :invalid_code | :expired | :too_many_attempts}
  def confirm_login(email, code) do
    with {:ok, norm} <- normalize_or_invalid_code(email) do
      case login_account_by_email(norm) do
        %Account{} = account ->
          with {:ok, row} <- match_code(account.id, "login", code) do
            {:ok, _} = Repo.delete(row)
            {:ok, account}
          end

        nil ->
          burn()
          {:error, :invalid_code}
      end
    end
  end

  @doc "The local account allowed to log in with this address, or nil."
  @spec login_account_by_email(String.t()) :: Account.t() | nil
  def login_account_by_email(email) when is_binary(email) do
    from(a in Account,
      where:
        is_nil(a.domain) and not is_nil(a.email_verified_at) and
          fragment("lower(?)", a.email) == ^String.downcase(email)
    )
    |> Repo.one()
  end

  # ── shared internals ─────────────────────────────────────────────────────

  defp issue(%Account{id: account_id} = account, purpose, email) do
    code = generate_code()
    expires_at = DateTime.add(utc_now(), @code_ttl_seconds, :second)

    {:ok, _} =
      Repo.insert(
        %EmailCode{
          account_id: account_id,
          email: email,
          purpose: purpose,
          code_hash: hash(code),
          attempts: 0,
          expires_at: expires_at
        },
        on_conflict: {:replace, [:email, :code_hash, :attempts, :expires_at, :created_at]},
        conflict_target: [:account_id, :purpose]
      )

    case Mailer.deliver(email, subject(), body(account, code)) do
      :ok -> :ok
      {:error, _} -> {:error, :send_failed}
    end
  end

  defp match_code(account_id, purpose, input) do
    input = input |> to_string() |> String.replace(~r/\s/, "")
    row = Repo.get_by(EmailCode, account_id: account_id, purpose: purpose)
    now = utc_now()

    cond do
      is_nil(row) ->
        burn()
        {:error, :invalid_code}

      DateTime.compare(row.expires_at, now) == :lt ->
        {:error, :expired}

      row.attempts >= @max_attempts ->
        {:error, :too_many_attempts}

      Plug.Crypto.secure_compare(row.code_hash, hash(input)) ->
        {:ok, row}

      true ->
        _ =
          from(c in EmailCode, where: c.id == ^row.id)
          |> Repo.update_all(inc: [attempts: 1])

        {:error, :invalid_code}
    end
  end

  # Only a *verified* claim blocks the address (matching the partial
  # unique index): an unverified signup entry must not let anyone
  # squat a mailbox they don't own.
  defp check_available(email, account_id) do
    taken? =
      from(a in Account,
        where:
          is_nil(a.domain) and a.id != ^account_id and
            not is_nil(a.email_verified_at) and
            fragment("lower(?)", a.email) == ^email
      )
      |> Repo.exists?()

    if taken?, do: {:error, :email_taken}, else: :ok
  end

  defp check_rate(email, account_id) do
    {limit, scale} = @send_per_email
    {acct_limit, acct_scale} = @send_per_account

    with {:allow, _} <- Hammer.check_rate("email_code:addr:#{email}", scale, limit),
         {:allow, _} <- account_rate(account_id, acct_scale, acct_limit) do
      :ok
    else
      {:deny, _} -> {:error, :rate_limited}
    end
  end

  defp account_rate(nil, _scale, _limit), do: {:allow, 0}

  defp account_rate(account_id, scale, limit),
    do: Hammer.check_rate("email_code:acct:#{account_id}", scale, limit)

  @doc """
  Trim + downcase + shape-check, the one user-facing rule for "is this
  an email". Signup (`LocalAccounts.create/1`) runs addresses through
  here too, so the same strings pass everywhere; the changeset-level
  `Account.validate_email/1` repeats the format only as the last line
  of defence for paths that skip this.
  """
  @spec normalize_email(term()) :: {:ok, String.t()} | {:error, :invalid_email}
  def normalize_email(email) do
    norm = email |> to_string() |> String.trim() |> String.downcase()

    if norm =~ ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/ and byte_size(norm) <= 254 do
      {:ok, norm}
    else
      {:error, :invalid_email}
    end
  end

  # The login-confirm path speaks only in `:invalid_code` for anything
  # that would otherwise reveal whether the address exists.
  defp normalize_or_invalid_code(email) do
    case normalize_email(email) do
      {:ok, norm} -> {:ok, norm}
      {:error, :invalid_email} -> {:error, :invalid_code}
    end
  end

  # Flatten timing between "no such account/code" and "wrong code" by
  # doing the same hash + compare work on the miss path.
  defp burn do
    # `secure_compare` of two fresh hashes is always false; the value is
    # the work, not the result.
    _ = Plug.Crypto.secure_compare(hash("000000"), hash("999999"))
    :ok
  end

  defp generate_code do
    <<n::32>> = :crypto.strong_rand_bytes(4)

    n
    |> rem(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end

  defp subject do
    "[#{domain()}] 認証コード / 인증 코드"
  end

  defp body(%Account{username: username}, code) do
    """
    @#{username} さん / @#{username} 님

    #{domain()} の認証コードです。/ #{domain()} 의 인증 코드입니다.

        #{code}

    10分のあいだ、有効です。/ 10분 동안 유효합니다.

    心当たりがなければ、このメールは、そっと捨ててください。
    짚이는 데가 없다면, 이 메일은 그냥 버려 주세요.
    """
  end

  defp domain, do: Application.get_env(:sukhi_fedi, :domain, "localhost:4000")

  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
