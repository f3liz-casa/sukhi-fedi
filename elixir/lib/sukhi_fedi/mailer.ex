# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Mailer do
  @moduledoc """
  Transactional mail: verification codes and login codes, nothing else.

  The transport is picked by config (`config :sukhi_fedi, :mailer`):
  `Mailer.SMTP` (gen_smtp → OCI Email Delivery or any relay) in prod,
  `Mailer.Log` when SMTP isn't configured, `Mailer.Capture` in tests.
  Callers just say `Mailer.deliver(to, subject, body)` and treat
  `{:error, _}` as "the mail did not go out" — honestly, to the user.

  The address sanity check lives here, once: anything with whitespace
  or separators in it could smuggle extra headers/recipients into the
  SMTP conversation, so it never reaches a transport.
  """

  require Logger

  @callback deliver(conf :: keyword(), to :: String.t(), subject :: String.t(), body :: String.t()) ::
              :ok | {:error, term()}

  @spec deliver(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def deliver(to, subject, body)
      when is_binary(to) and is_binary(subject) and is_binary(body) do
    conf = Application.get_env(:sukhi_fedi, :mailer, [])
    transport = conf[:transport] || SukhiFedi.Mailer.Log

    if to =~ ~r/^[^\s,;]+@[^\s,;]+$/ do
      transport.deliver(conf, to, subject, body)
    else
      {:error, :bad_address}
    end
  end

  @doc """
  The full RFC 5322 message bytes for an outgoing mail. Subject is
  RFC 2047 encoded-word (it is almost always Japanese/Korean), the
  body goes base64 so no relay on the way trips over raw UTF-8.
  """
  @spec render(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def render(from, to, subject, body) do
    date = Calendar.strftime(DateTime.utc_now(), "%a, %d %b %Y %H:%M:%S +0000")

    """
    From: #{from}\r
    To: #{to}\r
    Date: #{date}\r
    Subject: =?utf-8?B?#{Base.encode64(subject)}?=\r
    MIME-Version: 1.0\r
    Content-Type: text/plain; charset=utf-8\r
    Content-Transfer-Encoding: base64\r
    \r
    #{wrap76(Base.encode64(body))}
    """
  end

  defp wrap76(b64) do
    b64
    |> String.codepoints()
    |> Enum.chunk_every(76)
    |> Enum.map_join("\r\n", &Enum.join/1)
  end
end

defmodule SukhiFedi.Mailer.SMTP do
  @moduledoc """
  gen_smtp transport: STARTTLS on the configured port (587 for OCI
  Email Delivery), AUTH always, and real certificate verification —
  a code that can take over an account must not be MITM-able.
  """

  @behaviour SukhiFedi.Mailer

  require Logger

  @impl true
  def deliver(conf, to, subject, body) do
    from = Keyword.fetch!(conf, :from)
    host = Keyword.fetch!(conf, :host)
    message = SukhiFedi.Mailer.render(from, to, subject, body)

    opts = [
      relay: host,
      port: Keyword.get(conf, :port, 587),
      username: Keyword.fetch!(conf, :username),
      password: Keyword.fetch!(conf, :password),
      auth: :always,
      tls: :always,
      tls_options: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: String.to_charlist(host),
        depth: 3,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    case :gen_smtp_client.send_blocking({from, [to], message}, opts) do
      receipt when is_binary(receipt) ->
        :ok

      {:error, type, detail} ->
        Logger.warning("mailer: smtp send failed type=#{inspect(type)} detail=#{inspect(detail)}")
        {:error, {type, detail}}

      {:error, reason} ->
        Logger.warning("mailer: smtp send failed reason=#{inspect(reason)}")
        {:error, reason}
    end
  end
end

defmodule SukhiFedi.Mailer.Log do
  @moduledoc """
  No-SMTP fallback: the mail goes to the log, plainly marked. Dev sees
  the code right in the console; a prod box without SMTP_* env vars
  fails visibly instead of silently eating signups.
  """

  @behaviour SukhiFedi.Mailer

  require Logger

  @impl true
  def deliver(_conf, to, subject, body) do
    Logger.info("mailer (log transport, NOT delivered): to=#{to} subject=#{subject}\n#{body}")
    :ok
  end
end
