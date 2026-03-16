defmodule NKEYS do
  alias NKEYS.Keypair

  @doc deprecated: "Please use the `NKEYS.Keypair.from_seed/1` function instead"
  def from_seed(seed) when is_binary(seed) do
    Keypair.from_seed(seed)
  end

  @doc deprecated: "Please use the `NKEYS.Keypair.public_key/1` function instead"
  def public_nkey(keypair) do
    Keypair.public_key(keypair)
  end

  @doc deprecated: "Please use the `NKEYS.Keypair.sign/2` function instead"
  def sign(keypair, message) do
    Keypair.sign(keypair, message)
  end
end
