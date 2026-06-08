# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addons.Media.DimensionsTest do
  use ExUnit.Case, async: true

  alias SukhiFedi.Addons.Media.Dimensions

  test "reads PNG dimensions from the IHDR chunk" do
    png =
      <<0x89, "PNG\r\n", 0x1A, 0x0A, 13::32, "IHDR", 800::32, 600::32, 8, 6, 0, 0, 0>>

    assert Dimensions.measure(png) == {800, 600}
  end

  test "reads GIF dimensions from the logical screen descriptor" do
    gif = <<"GIF89a", 320::little-16, 240::little-16, 0, 0, 0>>
    assert Dimensions.measure(gif) == {320, 240}
  end

  test "reads JPEG dimensions from the SOF0 segment" do
    # APP0 (JFIF) header then a SOF0 carrying 480 high x 640 wide.
    app0 = <<0xFF, 0xE0, 16::16, "JFIF", 0, 1, 1, 0, 0, 1, 0, 1, 0, 0>>
    sof0 = <<0xFF, 0xC0, 17::16, 8, 480::16, 640::16, 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1>>
    jpeg = <<0xFF, 0xD8, app0::binary, sof0::binary>>

    assert Dimensions.measure(jpeg) == {640, 480}
  end

  test "reads lossy WebP (VP8) dimensions" do
    vp8 =
      <<"RIFF", 0::32, "WEBP", "VP8 ", 0::32, 0::24, 0x9D, 0x01, 0x2A, 1024::little-16,
        768::little-16>>

    assert Dimensions.measure(vp8) == {1024, 768}
  end

  test "returns nil for unrecognised bytes" do
    assert Dimensions.measure(<<"not an image at all">>) == nil
    assert Dimensions.measure(<<>>) == nil
  end
end
