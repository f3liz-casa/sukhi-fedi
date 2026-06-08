# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addons.Media.Dimensions do
  @moduledoc """
  Read an image's pixel width/height straight from its header bytes —
  no decode, no native dependency. Just enough format coverage for what
  browsers upload (PNG, JPEG, GIF, WebP). Anything we don't recognise
  returns `nil` and the upload still succeeds without dimensions.

  Dimensions matter for two things: the AP `attachment` (so a remote
  client can reserve the right box) and the Mastodon `meta.original`
  (so our own web client doesn't reflow when the image loads).
  """

  import Bitwise

  @spec measure(binary()) :: {pos_integer(), pos_integer()} | nil
  def measure(<<0x89, "PNG\r\n", 0x1A, 0x0A, _len::32, "IHDR", w::32, h::32, _::binary>>)
      when w > 0 and h > 0,
      do: {w, h}

  def measure(<<"GIF8", _v, ?a, w::little-16, h::little-16, _::binary>>)
      when w > 0 and h > 0,
      do: {w, h}

  def measure(<<"RIFF", _size::32, "WEBP", rest::binary>>), do: webp(rest)

  def measure(<<0xFF, 0xD8, rest::binary>>), do: jpeg(rest)

  def measure(_), do: nil

  # ── JPEG ───────────────────────────────────────────────────────────────
  # Walk marker segments until a Start-Of-Frame (SOF0..SOF3, SOF5..SOF7,
  # SOF9..SOF11, SOF13..SOF15) carries height then width as 16-bit BE.
  defp jpeg(<<0xFF, marker, len::16, seg::binary>>) when marker in 0xC0..0xCF and
                                                          marker not in [0xC4, 0xC8, 0xCC] do
    case seg do
      <<_precision, h::16, w::16, _::binary>> when w > 0 and h > 0 -> {w, h}
      _ -> skip_jpeg(len, seg)
    end
  end

  defp jpeg(<<0xFF, _marker, len::16, seg::binary>>), do: skip_jpeg(len, seg)
  defp jpeg(<<0xFF, rest::binary>>), do: jpeg(rest)
  defp jpeg(_), do: nil

  # `len` counts itself (2 bytes) plus the payload; `seg` already starts
  # past `len`, so drop `len - 2` payload bytes to reach the next marker.
  defp skip_jpeg(len, seg) when len >= 2 do
    payload = len - 2

    case seg do
      <<_skip::binary-size(^payload), next::binary>> -> jpeg(next)
      _ -> nil
    end
  end

  defp skip_jpeg(_, _), do: nil

  # ── WebP ───────────────────────────────────────────────────────────────
  # Three sub-formats share the RIFF/WEBP wrapper.
  defp webp(<<"VP8 ", _len::32, _frame_tag::24, 0x9D, 0x01, 0x2A, w::little-16, h::little-16,
              _::binary>>) do
    {w &&& 0x3FFF, h &&& 0x3FFF}
  end

  defp webp(<<"VP8L", _len::32, 0x2F, bits::little-32, _::binary>>) do
    # 14-bit width-1 then 14-bit height-1, packed little-endian.
    w = (bits &&& 0x3FFF) + 1
    h = (bits >>> 14 &&& 0x3FFF) + 1
    {w, h}
  end

  defp webp(<<"VP8X", _len::32, _flags::32, w::little-24, h::little-24, _::binary>>) do
    {w + 1, h + 1}
  end

  defp webp(_), do: nil
end
