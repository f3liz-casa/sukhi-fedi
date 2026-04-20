# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addons.MFM do
  @moduledoc """
  Misskey Flavored Markdown sanitization and plain-text extraction.
  Utility addon; no supervision children, no migrations.
  """

  use SukhiFedi.Addon, id: :mfm

  def sanitize(text) when is_binary(text) do
    text
    |> strip_dangerous_html()
    |> validate_mfm_syntax()
  end

  def to_plain_text(mfm) when is_binary(mfm) do
    mfm
    |> String.replace(~r/\$\[[^\]]*\]/, "")
    |> String.replace(~r/\*\*([^*]+)\*\*/, "\\1")
    |> String.replace(~r/__([^_]+)__/, "\\1")
    |> String.replace(~r/~~([^~]+)~~/, "\\1")
    |> String.replace(~r/`([^`]+)`/, "\\1")
    |> String.trim()
  end

  defp strip_dangerous_html(text) do
    text
    |> String.replace(~r/<script[^>]*>.*?<\/script>/is, "")
    |> String.replace(~r/<iframe[^>]*>.*?<\/iframe>/is, "")
    |> String.replace(~r/<object[^>]*>.*?<\/object>/is, "")
    |> String.replace(~r/<embed[^>]*>/is, "")
    |> String.replace(~r/on\w+\s*=/i, "")
  end

  defp validate_mfm_syntax(text) do
    if balanced_brackets?(text) do
      text
    else
      String.replace(text, ~r/\$\[[^\]]*\]/, "")
    end
  end

  defp balanced_brackets?(text) do
    text
    |> String.graphemes()
    |> Enum.reduce(0, fn
      "[", acc -> acc + 1
      "]", acc -> acc - 1
      _, acc -> acc
    end)
    |> Kernel.==(0)
  end
end
