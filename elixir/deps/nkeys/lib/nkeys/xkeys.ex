defmodule NKEYS.Xkeys do
  @moduledoc """
  Contains functions for using curve (X) keys for sending and receiving encrypted
  messages
  """
  @nonce_size 24
  @xkeyversion1 "xkv1"

  @spec seal(input :: binary(), their_public :: binary(), our_secret :: binary()) :: binary()
  @doc """
  Performs authenticated encryption by creating a ed25519 "box". Note that the keys passed to this
  function need to be raw keys, e.g. `keypair.public_key` and `keypair.private_key` and must **_not_**
  be in the human-friendly string encoding format.
  """
  def seal(input, their_public, our_secret) do
    # Generate a random 24-byte nonce
    nonce = :crypto.strong_rand_bytes(@nonce_size)

    # Perform authenticated encryption using the KCL box_seal function
    {sealed, _} = Kcl.box(input, nonce, our_secret, their_public)

    @xkeyversion1 <> nonce <> sealed
  end

  @spec open(input :: binary(), our_secret :: binary(), their_public :: binary()) ::
          {:ok, binary()} | :error
  @doc """
  Performs authenticated decryption by extracting data from the ed25519 "box". Note that the
  keys passed to this function need to come from the `NKEYS.Keypair` struct fields and must
  not be human-friendly encoded strings.
  """
  def open(input, our_secret, their_public) do
    <<_version::binary-size(4), nonce::binary-size(@nonce_size), message::binary>> = input

    case Kcl.unbox(message, nonce, our_secret, their_public) do
      {:error, _reason} -> :error
      {binary, _} -> {:ok, binary}
    end
  end
end
