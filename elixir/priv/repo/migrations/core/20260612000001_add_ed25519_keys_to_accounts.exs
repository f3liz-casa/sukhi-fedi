# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddEd25519KeysToAccounts do
  use Ecto.Migration

  @moduledoc """
  Ed25519 actor keys for FEP-8b32 Object Integrity Proofs
  (eddsa-jcs-2022), next to the existing RSA pair.

    * `ed25519_private_key_jwk` — OKP JWK, read by the delivery node to
      attach a `proof` to outbound activities.
    * `ed25519_public_multibase` — the Multikey `publicKeyMultibase`
      form (`z6Mk…`), precomputed so both ActorJson modules (gateway and
      delivery) publish `assertionMethod` without needing base58 —
      the same pattern as the stored `public_key_pem`.

  Existing local actors are backfilled here; new ones get their pair
  from `KeyGen.generate/0`. The key math is inlined rather than calling
  app modules so the migration stays frozen as written.
  """

  # base58btc alphabet (multibase `z`).
  @alphabet ~c"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

  def up do
    alter table(:accounts) do
      add(:ed25519_private_key_jwk, :map)
      add(:ed25519_public_multibase, :string)
    end

    flush()

    # Local actors only (`domain IS NULL`); remote rows mirror keys from
    # their home server's actor document instead.
    %{rows: rows} =
      repo().query!(
        "SELECT id FROM accounts WHERE domain IS NULL AND private_key_jwk IS NOT NULL"
      )

    for [id] <- rows do
      {public, private} = :crypto.generate_key(:eddsa, :ed25519)

      jwk = %{
        "kty" => "OKP",
        "crv" => "Ed25519",
        "x" => Base.url_encode64(public, padding: false),
        "d" => Base.url_encode64(private, padding: false)
      }

      # Pass the map itself: the parameter's inferred type is jsonb, so
      # postgrex encodes the term. Handing it pre-encoded JSON text gets
      # double-wrapped into a jsonb string (see the 000002 repair).
      repo().query!(
        """
        UPDATE accounts
        SET ed25519_private_key_jwk = $1::jsonb, ed25519_public_multibase = $2
        WHERE id = $3
        """,
        [jwk, multibase(public), id]
      )
    end
  end

  def down do
    alter table(:accounts) do
      remove(:ed25519_private_key_jwk)
      remove(:ed25519_public_multibase)
    end
  end

  # multicodec ed25519-pub (0xed 0x01) + base58btc with `z` prefix.
  defp multibase(public_key) do
    "z" <> base58(:crypto.bytes_to_integer(<<0xED, 0x01>> <> public_key), [])
  end

  defp base58(0, acc), do: List.to_string(acc)
  defp base58(n, acc), do: base58(div(n, 58), [Enum.at(@alphabet, rem(n, 58)) | acc])
end
