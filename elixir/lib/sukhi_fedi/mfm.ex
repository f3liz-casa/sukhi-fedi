# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.MFM do
  @moduledoc "Misskey Flavored Markdown sanitization and storage"

  # Allowed MFM syntax patterns (client-side rendering)
  @allowed_patterns ~w(
    $[spin $[x2 $[x3 $[x4 $[blur $[font $[rainbow
    $[sparkle $[rotate $[jump $[bounce $[shake $[twitch
    $[jelly $[tada $[flip $[scale $[position
    ** __ ~~ ` ``` > * - [ ] [x]
  )

  def sanitize(text) when is_binary(text) do
    text
    |> strip_dangerous_html()
    |> validate_mfm_syntax()
  end

  # Remove any HTML tags except basic formatting
  defp strip_dangerous_html(text) do
    text
    |> String.replace(~r/<script[^>]*>.*?<\/script>/is, "")
    |> String.replace(~r/<iframe[^>]*>.*?<\/iframe>/is, "")
    |> String.replace(~r/<object[^>]*>.*?<\/object>/is, "")
    |> String.replace(~r/<embed[^>]*>/is, "")
    |> String.replace(~r/on\w+\s*=/i, "")
  end

  # Validate MFM syntax is well-formed
  defp validate_mfm_syntax(text) do
    # Ensure brackets are balanced
    if balanced_brackets?(text) do
      text
    else
      # Strip MFM if malformed
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

  # Extract plain text (for search/preview)
  def to_plain_text(mfm) when is_binary(mfm) do
    mfm
    |> String.replace(~r/\$\[[^\]]*\]/, "")
    |> String.replace(~r/\*\*([^*]+)\*\*/, "\\1")
    |> String.replace(~r/__([^_]+)__/, "\\1")
    |> String.replace(~r/~~([^~]+)~~/, "\\1")
    |> String.replace(~r/`([^`]+)`/, "\\1")
    |> String.trim()
  end
end
