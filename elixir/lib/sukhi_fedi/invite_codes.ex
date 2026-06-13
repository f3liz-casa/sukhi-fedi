# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.InviteCodes do
  @moduledoc """
  Invite-code context. Admin UI calls `issue/2` to mint a code; the
  signup API calls `consume/2` inside the registration transaction.
  Single-use: a code with `consumed_at IS NOT NULL` is dead.
  """

  import Ecto.Query

  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Account, InviteCode}

  @code_bytes 9

  @spec issue(Account.t() | integer(), keyword()) :: {:ok, InviteCode.t()}
  def issue(issued_by, opts \\ [])
  def issue(%Account{id: id}, opts), do: issue(id, opts)
  def issue(issued_by_id, opts) when is_integer(issued_by_id) do
    code = generate_code()
    attrs = %{
      code: code,
      issued_by_id: issued_by_id,
      note: opts[:note],
      expires_at: opts[:expires_at]
    }

    %InviteCode{}
    |> Ecto.Changeset.cast(attrs, [:code, :issued_by_id, :note, :expires_at])
    |> Ecto.Changeset.validate_required([:code])
    |> Repo.insert()
  end

  @spec list(keyword()) :: [InviteCode.t()]
  def list(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    from(c in InviteCode, order_by: [desc: c.id], limit: ^limit)
    |> Repo.all()
    |> Repo.preload([:issued_by, :consumed_by])
  end

  @doc """
  Atomically mark a code as consumed by `consumer_id`. Returns:

    * `{:ok, invite}` on success
    * `{:error, :invalid}` if no such code
    * `{:error, :already_used}` if `consumed_at` was already set
    * `{:error, :expired}` if past `expires_at`

  Intended to be called inside the signup `Repo.transaction/1` so a
  failed account insert rolls the consumption back.
  """
  @spec consume(String.t(), integer()) ::
          {:ok, InviteCode.t()} | {:error, :invalid | :already_used | :expired}
  def consume(code, consumer_id) when is_binary(code) and is_integer(consumer_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(InviteCode, code: code) do
      nil ->
        {:error, :invalid}

      %InviteCode{} = ic ->
        case classify(ic, now) do
          :ok -> mark_consumed(ic, consumer_id, now)
          err -> {:error, err}
        end
    end
  end

  @doc """
  Read a code's liveness without consuming it. The `/invite/:code`
  landing page calls this (over RPC) to greet a visitor before signup —
  it reports who issued the code but leaves `consumed_at` untouched; the
  actual claim still happens inside the signup transaction via `consume/2`.

    * `{:ok, %{issuer_handle: ..., issuer_display_name: ...}}` when live
    * `{:error, :invalid | :already_used | :expired}` otherwise
  """
  @spec preview(String.t()) ::
          {:ok, %{issuer_handle: String.t() | nil, issuer_display_name: String.t() | nil}}
          | {:error, :invalid | :already_used | :expired}
  def preview(code) when is_binary(code) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(InviteCode, code: code) do
      nil ->
        {:error, :invalid}

      %InviteCode{} = ic ->
        case classify(ic, now) do
          :ok ->
            %{issued_by: issuer} = Repo.preload(ic, :issued_by)

            {:ok,
             %{
               issuer_handle: issuer && issuer.username,
               issuer_display_name: issuer && issuer.display_name
             }}

          err ->
            {:error, err}
        end
    end
  end

  # コードの生死を「読むだけ」で分類する ─ consume はこれが :ok の
  # ときだけ atomic UPDATE に進み、preview はこれをそのまま返す。
  # 生死の判定を一箇所に集めて、consume と preview で二度書かない。
  defp classify(%InviteCode{consumed_at: %DateTime{}}, _now), do: :already_used

  defp classify(%InviteCode{expires_at: %DateTime{} = exp}, now) do
    if DateTime.compare(exp, now) == :gt, do: :ok, else: :expired
  end

  defp classify(%InviteCode{}, _now), do: :ok

  # Atomic claim: a conditional UPDATE guarded on `consumed_at IS NULL`,
  # requiring exactly one affected row. Under concurrent signups with the
  # same code only one UPDATE matches; the loser sees 0 rows and gets
  # `:already_used`, rolling back its account insert. The previous
  # read-then-write let one code mint N accounts (TOCTOU double-spend).
  defp mark_consumed(%InviteCode{id: id} = ic, consumer_id, now) do
    {n, _} =
      from(c in InviteCode, where: c.id == ^id and is_nil(c.consumed_at))
      |> Repo.update_all(set: [consumed_at: now, consumed_by_id: consumer_id])

    case n do
      1 -> {:ok, %{ic | consumed_at: now, consumed_by_id: consumer_id}}
      _ -> {:error, :already_used}
    end
  end

  defp generate_code do
    :crypto.strong_rand_bytes(@code_bytes)
    |> Base.encode32(case: :lower, padding: false)
  end
end
