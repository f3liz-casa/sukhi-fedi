# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Auth.TOTPTest do
  use ExUnit.Case, async: true

  alias SukhiFedi.Auth.TOTP

  # RFC 6238 Appendix B vectors (SHA-1, secret "12345678901234567890").
  # The RFC prints 8-digit codes; ours are the same truncation mod 10^6,
  # i.e. the last six digits of each printed value.
  @rfc_secret "12345678901234567890"

  test "matches the RFC 6238 SHA-1 test vectors" do
    for {t, expected} <- [
          {59, "287082"},
          {1_111_111_109, "081804"},
          {1_111_111_111, "050471"},
          {1_234_567_890, "005924"},
          {2_000_000_000, "279037"},
          {20_000_000_000, "353130"}
        ] do
      assert TOTP.code(@rfc_secret, div(t, 30)) == expected
    end
  end

  test "valid? accepts the current step and returns it" do
    now = 1_111_111_111
    assert {:ok, step} = TOTP.valid?(@rfc_secret, "050471", nil, now)
    assert step == div(now, 30)
  end

  test "valid? tolerates one step of drift either way" do
    now = 1_111_111_111
    # step-1 is T=1_111_111_109's window
    assert {:ok, _} = TOTP.valid?(@rfc_secret, "081804", nil, now)
    # step+1
    future = TOTP.code(@rfc_secret, div(now, 30) + 1)
    assert {:ok, _} = TOTP.valid?(@rfc_secret, future, nil, now)
    # step+2 is out of the window
    far = TOTP.code(@rfc_secret, div(now, 30) + 2)
    assert :error = TOTP.valid?(@rfc_secret, far, nil, now)
  end

  test "valid? refuses a replayed step" do
    now = 1_111_111_111
    {:ok, step} = TOTP.valid?(@rfc_secret, "050471", nil, now)
    assert :error = TOTP.valid?(@rfc_secret, "050471", step, now)
    # ...and anything older than the high-water mark
    assert :error = TOTP.valid?(@rfc_secret, "081804", step, now)
  end

  test "valid? ignores whitespace and rejects junk" do
    now = 1_111_111_111
    assert {:ok, _} = TOTP.valid?(@rfc_secret, " 050 471 ", nil, now)
    assert :error = TOTP.valid?(@rfc_secret, "abc123", nil, now)
    assert :error = TOTP.valid?(@rfc_secret, "12345", nil, now)
    assert :error = TOTP.valid?(@rfc_secret, "", nil, now)
  end

  test "otpauth_uri carries the secret in base32 and escapes the label" do
    secret = TOTP.generate_secret()
    uri = TOTP.otpauth_uri("usagi@example.tld", secret, "sukhi fedi")

    assert uri =~ "otpauth://totp/sukhi+fedi:usagi%40example.tld?"
    assert uri =~ "secret=#{Base.encode32(secret, padding: false)}"
    assert uri =~ "issuer=sukhi+fedi"
    assert uri =~ "digits=6"
  end
end
