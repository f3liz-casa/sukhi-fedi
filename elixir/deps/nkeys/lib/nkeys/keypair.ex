defmodule NKEYS.Keypair do
  @moduledoc """
  Contains functions for creating, manipulating, and interacting with key pairs
  """
  import Bitwise

  defstruct [:seed, :public_key, :private_key, :prefix]

  @type t :: %__MODULE__{
          seed: String.t(),
          public_key: binary(),
          private_key: binary(),
          prefix: byte()
        }

  # PREFIX_BYTE_SEED is the version byte used for encoded NATS Seeds
  # Base32-encodes to 'S...'
  @prefix_seed 18

  # PREFIX_PRIVATE is the version byte used for encoded NATS Private keys
  # @prefix_private 15 # Base32-encodes to 'P...'

  # PREFIX_SERVER is the version byte used for encoded NATS Servers
  # Base32-encodes to 'N...'
  @prefix_server 13

  # PREFIX_CLUSTER is the version byte used for encoded NATS Clusters
  # Base32-encodes to 'C...'
  @prefix_cluster 2

  # PREFIX_OPERATOR is the version byte used for encoded NATS Operators
  # Base32-encodes to 'O...'
  @prefix_operator 14

  # PREFIX_ACCOUNT is the version byte used for encoded NATS Accounts
  # Base32-encodes to 'A...'
  @prefix_account 0

  # PREFIX_USER is the version byte used for encoded NATS Users
  # Base32-encodes to 'U...'
  @prefix_user 20

  # PREFIX_BYTECURVE is the version byte used for encoded CurveKeys (X25519)
  # Base32-encodes to 'X...'
  @prefix_xcurve 23

  @valid_nkey_types [
    @prefix_account,
    @prefix_cluster,
    @prefix_operator,
    @prefix_server,
    @prefix_user,
    @prefix_xcurve
  ]

  @spec new_account() :: t()
  @doc """
  Creates a new key pair used for identifying an account (prefix '**A**')
  """
  def new_account() do
    new_pair(@prefix_account)
  end

  @spec new_cluster() :: t()
  @doc """
  Creates a new key pair used for identifying a cluster (prefix '**C**')
  """
  def new_cluster() do
    new_pair(@prefix_cluster)
  end

  @spec new_operator() :: t()
  @doc """
  Creates a new key pair used for identifying a system operator (prefix '**O**')
  """
  def new_operator() do
    new_pair(@prefix_operator)
  end

  @spec new_server() :: t()
  @doc """
  Creates a new key pair used for identifying a server (prefix '**N**')
  """
  def new_server() do
    new_pair(@prefix_server)
  end

  @spec new_user() :: t()
  @doc """
  Creates a new key pair used for identifying a user (prefix '**U**')
  """
  def new_user() do
    new_pair(@prefix_user)
  end

  @spec new_xkey() :: t()
  @doc """
  Creates a new key pair used for ed25519 encryption (prefix '**X**')
  """
  def new_xkey() do
    new_pair(@prefix_xcurve)
  end

  defp new_pair(prefix) when prefix in @valid_nkey_types do
    {private, public} = Ed25519.generate_key_pair()

    %__MODULE__{
      public_key: public,
      private_key: private,
      seed: "",
      prefix: prefix
    }
  end

  @spec public_key(t()) :: String.t()
  @doc """
  Extracts the human-friendly, string-encoded public key from the keypair
  """
  def public_key(%__MODULE__{public_key: public_key, prefix: prefix}) do
    with_prefix = <<prefix::size(5), 0::size(3), public_key::binary>>
    crc = NKEYS.CRC.compute(with_prefix)
    Base.encode32(<<with_prefix::binary, crc::size(16)-little>>, padding: false)
  end

  @spec from_seed(seed :: binary()) :: {:ok, t()} | {:error, :invalid_seed}
  @doc """
  Creates a new key pair from an encoded seed string ('**S**' prefix)
  """
  def from_seed(seed) when is_binary(seed) do
    with {:ok, binary} <- Base.decode32(seed, case: :mixed, padding: false),
         <<p1::size(5), p2::size(5), _::size(6), raw_seed::binary-size(32),
           _crc::size(16)-little>> <- binary,
         true <- valid_seed_prefix?(p1, p2) do
      {private, public} = Ed25519.generate_key_pair(raw_seed)

      keypair = %__MODULE__{
        seed: seed,
        prefix: p2,
        public_key: public,
        private_key: private
      }

      {:ok, keypair}
    else
      _ ->
        {:error, :invalid_seed}
    end
  end

  @spec from_public(binary()) :: :error | t()
  @doc """
  Creates a new keypair from a string-encoded public key. Note that this keypair will _not_
  have a private key and as such won't be able to sign or encrypt
  """
  def from_public(public_key) when is_binary(public_key) do
    case decode(public_key) do
      {:ok, decoded, prefix} ->
        %__MODULE__{
          public_key: decoded,
          prefix: prefix
        }

      _ ->
        :error
    end
  end

  @spec sign(keypair :: t(), message :: binary()) :: binary()
  @doc """
  Signs a message with the given key pair. Note that the key pair
  must have a private key in order to create the signature.
  """
  def sign(%__MODULE__{public_key: public, private_key: private}, message)
      when is_binary(message) do
    Ed25519.signature(message, private, public)
  end

  @doc false
  def encode(prefix, src) do
    raw = [prefix | src] |> :binary.list_to_bin()
    crc = NKEYS.CRC.compute(raw)
    new = raw <> <<crc::little-16>>
    Base.encode32(new, padding: false)
  end

  @doc false
  def encode_seed(prefix, src) do
    b1 = @prefix_seed ||| prefix >>> 5
    b2 = (prefix &&& 31) <<< 3

    raw = [b1, b2 | src] |> :binary.list_to_bin()
    crc = NKEYS.CRC.compute(raw)
    new = raw <> <<crc::little-16>>
    Base.encode32(new, padding: false)
  end

  @doc false
  def decode(input) when is_binary(input) do
    with {:ok, raw} <- Base.decode32(input, padding: false),
         n <- byte_size(raw) do
      <<prefix::binary-size(1), in_stripped::binary-size(n - 3), crc::little-16>> = raw

      if NKEYS.CRC.compute(in_stripped) != crc do
        {:error, :bad_crc}
      else
        {:ok, in_stripped, prefix}
      end
    else
      _ -> {:error, :decoding_failure}
    end
  end

  defp valid_seed_prefix?(prefix1, prefix2) do
    prefix1 == @prefix_seed &&
      prefix2 in @valid_nkey_types
  end
end
