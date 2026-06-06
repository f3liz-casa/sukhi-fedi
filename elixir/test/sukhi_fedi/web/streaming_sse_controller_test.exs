# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.StreamingSseControllerTest do
  use ExUnit.Case, async: true

  alias SukhiFedi.Web.StreamingSseController, as: SSE

  describe "frame/2" do
    test "JSON-encodes a map payload into an SSE event/data frame" do
      out = IO.iodata_to_binary(SSE.frame("notification", %{"type" => "follow", "id" => "9"}))

      assert ["event: notification", "data: " <> data, "", ""] = String.split(out, "\n")
      assert JSON.decode!(data) == %{"type" => "follow", "id" => "9"}
    end

    test "passes a binary payload through unchanged" do
      out = IO.iodata_to_binary(SSE.frame("delete", "12345"))
      assert out == "event: delete\ndata: 12345\n\n"
    end

    test "every frame terminates with a blank line" do
      out = IO.iodata_to_binary(SSE.frame("notification", %{"x" => 1}))
      assert String.ends_with?(out, "\n\n")
    end
  end
end
