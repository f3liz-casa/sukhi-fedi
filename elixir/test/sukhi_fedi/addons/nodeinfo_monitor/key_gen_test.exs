# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addons.NodeinfoMonitor.KeyGenTest do
  use ExUnit.Case, async: true

  alias SukhiFedi.Addons.NodeinfoMonitor.KeyGen

  describe "generate/0" do
    test "produces a matched JWK/PEM triple" do
      %{public_jwk: pub, private_jwk: priv, public_pem: pem} = KeyGen.generate()

      assert pub["kty"] == "RSA"
      assert pub["alg"] == "RS256"
      assert is_binary(pub["n"])
      assert is_binary(pub["e"])
      assert byte_size(pub["n"]) > 300

      for k <- ~w(n e d p q dp dq qi) do
        assert is_binary(priv[k]), "expected private_jwk to have #{k}"
      end

      assert String.starts_with?(pem, "-----BEGIN PUBLIC KEY-----")
      assert String.ends_with?(String.trim_trailing(pem), "-----END PUBLIC KEY-----")

      [entry | _] = :public_key.pem_decode(pem)
      {:RSAPublicKey, n, e} = :public_key.pem_entry_decode(entry)
      assert is_integer(n)
      assert e == 65_537
    end

    test "each invocation yields a fresh key" do
      %{public_jwk: a} = KeyGen.generate()
      %{public_jwk: b} = KeyGen.generate()
      refute a["n"] == b["n"]
    end
  end
end
