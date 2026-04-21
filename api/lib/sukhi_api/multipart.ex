# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Multipart do
  @moduledoc """
  Minimal `multipart/form-data` parser for the api plugin node.

  The api node doesn't run a Plug pipeline (`Plug.Parsers` is gateway-
  side only), so capabilities receive raw bytes for multipart bodies.
  This parser handles the subset Mastodon clients actually emit:

    * one or more text fields:
      `Content-Disposition: form-data; name="<field>"`
    * exactly zero or one file part:
      `Content-Disposition: form-data; name="file"; filename="..."`
      `Content-Type: image/png` (or similar)

  Returns:

      {:ok, %{
        fields: %{"description" => "..."},
        file: %{
          name: "file",
          filename: "kitten.png",
          content_type: "image/png",
          bytes: <<...>>
        }
      }}

  or `{:ok, %{fields: %{}, file: nil}}` for body-less bodies, or
  `{:error, :bad_multipart | :no_boundary | :file_too_large}` on
  malformed input.

  Hard cap on file bytes is configurable via `:max_file_bytes` (default
  8 MiB to match Mastodon's default).
  """

  @default_max 8 * 1024 * 1024

  @spec parse(binary(), String.t(), keyword()) ::
          {:ok, map()} | {:error, atom()}
  def parse(body, content_type, opts \\ []) when is_binary(body) and is_binary(content_type) do
    max_bytes = Keyword.get(opts, :max_file_bytes, @default_max)

    case extract_boundary(content_type) do
      {:ok, boundary} -> parse_with_boundary(body, boundary, max_bytes)
      :error -> {:error, :no_boundary}
    end
  end

  defp extract_boundary(content_type) do
    parts = String.split(content_type, ";", trim: true) |> Enum.map(&String.trim/1)

    Enum.find_value(parts, :error, fn part ->
      case String.split(part, "=", parts: 2) do
        ["boundary", value] -> {:ok, strip_quotes(value)}
        _ -> nil
      end
    end)
  end

  defp strip_quotes(s) do
    s
    |> String.trim()
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
  end

  defp parse_with_boundary(body, boundary, max_bytes) do
    delim = "--" <> boundary

    parts =
      body
      |> :binary.split(delim, [:global])
      # First chunk before the first delimiter is preamble; last is the
      # `--` end marker plus epilogue. Drop both.
      |> Enum.drop(1)
      |> Enum.reject(fn p -> p == "" or String.starts_with?(p, "--") end)

    do_parse_parts(parts, %{fields: %{}, file: nil}, max_bytes)
  end

  defp do_parse_parts([], acc, _max), do: {:ok, acc}

  defp do_parse_parts([raw | rest], acc, max) do
    raw =
      raw
      |> strip_leading_crlf()
      |> strip_trailing_crlf()

    case split_headers_and_body(raw) do
      {:ok, header_block, body} ->
        case parse_part(header_block, body, max) do
          {:field, name, value} ->
            do_parse_parts(rest, put_in(acc, [:fields, name], value), max)

          {:file, file} ->
            do_parse_parts(rest, %{acc | file: file}, max)

          :ignore ->
            do_parse_parts(rest, acc, max)

          {:error, reason} ->
            {:error, reason}
        end

      :error ->
        {:error, :bad_multipart}
    end
  end

  defp split_headers_and_body(raw) do
    case :binary.split(raw, "\r\n\r\n") do
      [headers, body] -> {:ok, headers, body}
      _ -> :error
    end
  end

  defp parse_part(header_block, body, max) do
    headers = parse_headers(header_block)
    disposition = headers["content-disposition"] || ""
    content_type = headers["content-type"] || "application/octet-stream"

    fields = parse_disposition(disposition)
    name = fields["name"]
    filename = fields["filename"]

    cond do
      is_nil(name) ->
        :ignore

      not is_nil(filename) ->
        if byte_size(body) > max do
          {:error, :file_too_large}
        else
          {:file,
           %{
             name: name,
             filename: filename,
             content_type: content_type,
             bytes: body
           }}
        end

      true ->
        {:field, name, body}
    end
  end

  defp parse_headers(header_block) do
    header_block
    |> String.split("\r\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [k, v] -> Map.put(acc, String.downcase(String.trim(k)), String.trim(v))
        _ -> acc
      end
    end)
  end

  defp parse_disposition(disposition) do
    disposition
    |> String.split(";", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reduce(%{}, fn part, acc ->
      case String.split(part, "=", parts: 2) do
        [k, v] -> Map.put(acc, String.downcase(k), strip_quotes(v))
        _ -> acc
      end
    end)
  end

  defp strip_leading_crlf("\r\n" <> rest), do: rest
  defp strip_leading_crlf(other), do: other

  defp strip_trailing_crlf(s) do
    cond do
      String.ends_with?(s, "\r\n") -> binary_part(s, 0, byte_size(s) - 2)
      true -> s
    end
  end
end
