# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Auth.TOTP do
  @moduledoc """
  RFC 6238 time-based one-time passwords, the flavour every
  authenticator app speaks by default: HMAC-SHA-1, 6 digits, 30-second
  steps. Pure functions only — secret storage and the enabled/disabled
  state live on the account row, rate limiting lives at the endpoint.

  Replay is the one stateful thing: a verified code's step must be
  remembered (`accounts.totp_last_used_step`) and `valid?/3` refuses
  any step at or below it, so a shoulder-surfed code dies the moment
  the real one is used.
  """

  import Bitwise

  @period 30
  # Accept the neighbouring steps too: phone clocks drift, people type
  # slowly. ±1 step = ±30 s, the common server-side default.
  @window 1

  @spec generate_secret() :: binary()
  def generate_secret, do: :crypto.strong_rand_bytes(20)

  @doc """
  Check `input` against `secret` within the drift window, rejecting
  steps already used. Returns `{:ok, step}` so the caller can persist
  the new high-water mark, or `:error`.
  """
  @spec valid?(binary(), String.t(), integer() | nil, integer()) :: {:ok, integer()} | :error
  def valid?(secret, input, last_used_step, now \\ System.os_time(:second))
      when is_binary(secret) do
    normalized = input |> to_string() |> String.replace(~r/\s/, "")
    current = div(now, @period)
    floor = last_used_step || -1

    if normalized =~ ~r/^\d{6}$/ do
      Enum.find_value(-@window..@window, :error, fn drift ->
        step = current + drift

        if step > floor and Plug.Crypto.secure_compare(code(secret, step), normalized) do
          {:ok, step}
        end
      end)
    else
      :error
    end
  end

  @doc "The 6-digit code for one counter step (RFC 4226 truncation)."
  @spec code(binary(), integer()) :: String.t()
  def code(secret, step) do
    hmac = :crypto.mac(:hmac, :sha, secret, <<step::64>>)
    offset = :binary.last(hmac) &&& 0x0F
    <<_::binary-size(^offset), _::1, truncated::31, _::binary>> = hmac

    truncated
    |> rem(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end

  @doc """
  The `otpauth://` provisioning URI authenticator apps import (shown as
  a QR by the SPA, and as a plain link/secret for manual entry).
  """
  @spec otpauth_uri(String.t(), binary(), String.t()) :: String.t()
  def otpauth_uri(label, secret, issuer) do
    base32 = Base.encode32(secret, padding: false)
    enc = &URI.encode_www_form/1

    "otpauth://totp/#{enc.(issuer)}:#{enc.(label)}" <>
      "?secret=#{base32}&issuer=#{enc.(issuer)}&algorithm=SHA1&digits=6&period=#{@period}"
  end
end
