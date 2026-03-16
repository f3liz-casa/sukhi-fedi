defmodule Poly1305 do
  require Chacha20
  import Bitwise

  @moduledoc """
  Poly1305 message authentication

  https://tools.ietf.org/html/rfc7539
  """
  @typedoc """
  Encryption key
  """
  @type key :: binary
  @typedoc """
  Per-message nonce

  By convention, the first 4 bytes should be sender-specific.
  The trailing 8 bytes may be as simple as a counter.
  """
  @type nonce :: binary
  @typedoc """
  MAC tag
  """
  @type tag :: binary

  defp clamp(r), do: r &&& 0x0FFFFFFC0FFFFFFC0FFFFFFC0FFFFFFF

  defp split_key(k),
    do:
      {k |> binary_part(0, 16) |> :binary.decode_unsigned(:little) |> clamp,
       k |> binary_part(16, 16) |> :binary.decode_unsigned(:little)}

  defp p, do: 0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFB

  @doc """
  Compute a Message authentication code

  The one-time key should never be reused.
  """
  @spec hmac(binary, key) :: tag
  def hmac(m, k) do
    {r, s} = split_key(k)
    val = process_message(m, r, 0) + s

    val
    |> :binary.encode_unsigned(:little)
    |> result_align
  end

  @doc false
  def key_gen(k, n), do: k |> Chacha20.block(n, 0) |> binary_part(0, 32)

  defp result_align(s) when byte_size(s) >= 16, do: binary_part(s, 0, 16)
  defp result_align(s) when byte_size(s) < 16, do: align_pad(s, 16)

  defp int_pow_two(n), do: 2 |> :math.pow(n) |> round

  defp process_message(<<>>, _r, a), do: a

  defp process_message(<<i::unsigned-little-integer-size(128), rest::binary>>, r, a),
    do: process_message(rest, r, new_a(i, a, r, 128))

  defp process_message(m, r, a),
    do: m |> :binary.decode_unsigned(:little) |> new_a(a, r, bit_size(m))

  defp new_a(i, a, r, s), do: rem(r * (a + i + int_pow_two(s)), p())

  @doc """
    authenticated encryption with additional data - encryption

    - message to be encrypted
    - shared secret key
    - one-time use nonce
    - additional authenticated data

    The return value will be a tuple of `{ciphertext, MAC}`

    The algorithm is applied as described in RFC7539:

    - The key and nonce are used to encrypt the message with ChaCha20.
    - The one-time MAC key is derived from the cipher key and nonce.
    - The ciphertext and additional data are authenticated with the MAC
  """
  @spec aead_encrypt(binary, key, nonce, binary) :: {binary, tag}
  def aead_encrypt(m, k, n, a \\ "") do
    otk = key_gen(k, n)
    c = Chacha20.crypt(m, k, n, 1)
    md = align_pad(a, 16) <> align_pad(c, 16) <> msg_length(a) <> msg_length(c)

    {c, hmac(md, otk)}
  end

  @doc """
    authenticated encryption with additional data - decryption

    - encrypted message
    - shared secret key
    - one-time use nonce
    - additional authenticated data
    - MAC

    On success, returns the plaintext message.  If the message cannot be
    authenticated `:error` is returned.
  """
  @spec aead_decrypt(binary, key, nonce, binary, tag) :: binary | :error
  def aead_decrypt(c, k, n, a \\ "", t) do
    otk = key_gen(k, n)
    md = align_pad(a, 16) <> align_pad(c, 16) <> msg_length(a) <> msg_length(c)
    m = Chacha20.crypt(c, k, n, 1)
    if md |> hmac(otk) |> same_hmac?(t), do: m, else: :error
  end

  defp msg_length(s), do: s |> byte_size |> :binary.encode_unsigned(:little) |> align_pad(8)

  defp align_pad(s, n) do
    case s |> byte_size |> rem(n) do
      # Already the proper width
      0 ->
        s

      r ->
        s <> zeroes(n - r)
    end
  end

  defp zeroes(n), do: zero_loop(<<>>, n)
  defp zero_loop(z, 0), do: z
  defp zero_loop(z, n), do: zero_loop(z <> <<0>>, n - 1)

  @doc """
  compare two HMACs in constant time
  """
  @spec same_hmac?(binary, binary) :: boolean
  def same_hmac?(a, b), do: Equivalex.equal?(a, b)
end
