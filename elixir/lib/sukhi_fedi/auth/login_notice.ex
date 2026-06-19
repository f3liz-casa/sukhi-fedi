# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Auth.LoginNotice do
  @moduledoc """
  The one quiet heads-up: when a session is minted from a device the
  account has never signed in from before
  (`LocalAccounts.new_device?/2`), a single plain mail goes to the
  account's own verified address. Nothing more — no push, no in-app
  badge, no count. It is a courtesy after the fact, not a gate: the
  login already happened and the real second factor already ran.

  The IP is shown *coarse* on purpose — enough to tell "that was me, on
  my phone, at home" from "that was not me", without writing a precise
  address into a mailbox the recipient may read on a shared screen.
  """

  alias SukhiFedi.{Mailer, Schema.Account}

  @spec deliver(Account.t(), String.t() | nil) :: :ok | {:error, term()}
  def deliver(%Account{email: email, username: username}, ip) when is_binary(email) do
    Mailer.deliver(email, subject(), body(username, ip))
  end

  @doc """
  Blur an IP to a neighbourhood: the last octet of an IPv4 (`203.0.113.x`)
  or the first block of an IPv6 (`2001:x`). Anything unparseable — or a
  missing IP — becomes a plain "unknown" so the mail still reads.
  """
  @spec coarse_ip(String.t() | nil) :: String.t()
  def coarse_ip(ip) when is_binary(ip) do
    cond do
      String.contains?(ip, ":") ->
        [head | _] = String.split(ip, ":", parts: 2)
        head <> ":…"

      true ->
        case String.split(ip, ".") do
          [a, b, c, _d] -> Enum.join([a, b, c, "x"], ".")
          _ -> "?"
        end
    end
  end

  def coarse_ip(_), do: "?"

  defp subject do
    "[#{domain()}] あたらしい端末でログインがありました / 새 기기에서 로그인이 있었어요"
  end

  defp body(username, ip) do
    greeting =
      case username do
        nil -> ""
        name -> "@#{name} さん / @#{name} 님\n\n"
      end

    """
    #{greeting}#{domain()} に、あたらしい端末からログインがありました。
    #{domain()} 에, 새 기기에서 로그인이 있었어요.

        だいたいの場所 / 대략적인 위치: #{coarse_ip(ip)}

    心当たりがあれば、なにもしなくて大丈夫です。
    짚이는 데가 있다면, 아무것도 하지 않아도 괜찮아요.

    もし心当たりがなければ、ログインと安全のページから、いまの
    ログインを見直してください。
    만약 짚이는 데가 없다면, 로그인과 안전 페이지에서 지금의
    로그인을 살펴봐 주세요.

        https://#{domain()}/settings/security
    """
  end

  defp domain, do: Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
end
