# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.MultipartTest do
  use ExUnit.Case, async: true

  alias SukhiApi.Multipart

  defp build(boundary, parts) do
    delim = "--" <> boundary

    body =
      Enum.map_join(parts, "", fn p -> delim <> "\r\n" <> p <> "\r\n" end) <>
        delim <> "--\r\n"

    {body, "multipart/form-data; boundary=" <> boundary}
  end

  test "parses a single text field" do
    {body, ct} =
      build("---boundary123", [
        ~s|Content-Disposition: form-data; name="description"\r\n\r\na cute cat|
      ])

    assert {:ok, %{fields: %{"description" => "a cute cat"}, file: nil}} =
             Multipart.parse(body, ct)
  end

  test "parses a file part" do
    file_bytes = <<137, 80, 78, 71, 13, 10, 26, 10>>

    {body, ct} =
      build("xxBOUNDARYxx", [
        ~s|Content-Disposition: form-data; name="file"; filename="kitten.png"\r\nContent-Type: image/png\r\n\r\n| <>
          file_bytes
      ])

    assert {:ok, %{fields: %{}, file: file}} = Multipart.parse(body, ct)
    assert file.name == "file"
    assert file.filename == "kitten.png"
    assert file.content_type == "image/png"
    assert file.bytes == file_bytes
  end

  test "parses mixed text + file" do
    file_bytes = "JPEG_BYTES"

    {body, ct} =
      build("BB", [
        ~s|Content-Disposition: form-data; name="description"\r\n\r\nphoto|,
        ~s|Content-Disposition: form-data; name="file"; filename="x.jpg"\r\nContent-Type: image/jpeg\r\n\r\n| <>
          file_bytes
      ])

    assert {:ok, %{fields: %{"description" => "photo"}, file: file}} =
             Multipart.parse(body, ct)

    assert file.bytes == file_bytes
  end

  test "rejects body without boundary directive" do
    assert {:error, :no_boundary} = Multipart.parse("anything", "multipart/form-data")
  end

  test "enforces max_file_bytes" do
    big = :binary.copy(<<0>>, 1024)

    {body, ct} =
      build("BB", [
        ~s|Content-Disposition: form-data; name="file"; filename="big.bin"\r\nContent-Type: application/octet-stream\r\n\r\n| <>
          big
      ])

    assert {:error, :file_too_large} = Multipart.parse(body, ct, max_file_bytes: 256)
  end

  test "ignores parts with no name= attribute" do
    {body, ct} =
      build("BB", [
        ~s|Content-Disposition: form-data\r\n\r\norphan|
      ])

    assert {:ok, %{fields: %{}, file: nil}} = Multipart.parse(body, ct)
  end

  test "handles boundary with quoted value in content-type" do
    {body, ct_unquoted} =
      build("BB", [
        ~s|Content-Disposition: form-data; name="x"\r\n\r\nv|
      ])

    ct = ~s|multipart/form-data; boundary="BB"|
    assert {:ok, %{fields: %{"x" => "v"}}} = Multipart.parse(body, ct)

    # also works without quotes
    assert {:ok, %{fields: %{"x" => "v"}}} = Multipart.parse(body, ct_unquoted)
  end
end
