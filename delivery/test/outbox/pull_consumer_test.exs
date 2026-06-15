# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Outbox.PullConsumerTest do
  use ExUnit.Case, async: true

  alias SukhiDelivery.Outbox.PullConsumer, as: PC

  describe "delivered_count/1 — parsing the JetStream ack subject" do
    test "standard 9-token subject (no domain)" do
      # $JS.ACK.<stream>.<consumer>.<delivered>.<sseq>.<cseq>.<ts>.<pending>
      assert PC.delivered_count("$JS.ACK.OUTBOX.delivery-outbox.3.42.42.1700000000.0") == 3
    end

    test "11-token subject (JetStream domain + account hash)" do
      # $JS.ACK.<domain>.<hash>.<stream>.<consumer>.<delivered>.<sseq>.<cseq>.<ts>.<pending>
      assert PC.delivered_count("$JS.ACK.hub.AbC.OUTBOX.delivery-outbox.7.42.42.1700000000.0") == 7
    end

    test "12-token subject (trailing random token)" do
      assert PC.delivered_count("$JS.ACK.hub.AbC.OUTBOX.delivery-outbox.9.42.42.1700000000.0.xyz") ==
               9
    end

    test "unparseable / nil → 1 (retry, never a premature dead-letter)" do
      assert PC.delivered_count("garbage") == 1
      assert PC.delivered_count(nil) == 1
    end
  end

  describe "backoff_ms/1" do
    test "ramps with the attempt and clamps to the last step" do
      assert PC.backoff_ms(1) == 5_000
      assert PC.backoff_ms(2) == 10_000
      assert PC.backoff_ms(100) == 300_000
    end

    test "is always under the dead-letter attempt count of steps" do
      # one backoff defined for each retry before dead-lettering
      assert PC.backoff_ms(PC.max_attempts() - 1) == 300_000
    end
  end

  describe "dlq_subject/1" do
    test "maps an outbox subject to its dead-letter counterpart" do
      assert PC.dlq_subject("sns.outbox.note.created") == "sns.outbox_dlq.note.created"
      assert PC.dlq_subject("sns.outbox.follow.requested") == "sns.outbox_dlq.follow.requested"
    end

    test "leaves an unexpected subject prefixed, not dropped" do
      assert PC.dlq_subject("weird.subject") == "sns.outbox_dlq.weird.subject"
    end
  end
end
