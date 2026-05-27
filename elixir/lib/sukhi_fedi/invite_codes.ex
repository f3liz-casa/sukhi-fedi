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

      %InviteCode{consumed_at: %DateTime{}} ->
        {:error, :already_used}

      %InviteCode{expires_at: exp} = ic when not is_nil(exp) ->
        if DateTime.compare(exp, now) == :gt do
          mark_consumed(ic, consumer_id, now)
        else
          {:error, :expired}
        end

      %InviteCode{} = ic ->
        mark_consumed(ic, consumer_id, now)
    end
  end

  defp mark_consumed(%InviteCode{} = ic, consumer_id, now) do
    ic
    |> Ecto.Changeset.change(%{consumed_at: now, consumed_by_id: consumer_id})
    |> Repo.update()
  end

  defp generate_code do
    :crypto.strong_rand_bytes(@code_bytes)
    |> Base.encode32(case: :lower, padding: false)
  end
end
