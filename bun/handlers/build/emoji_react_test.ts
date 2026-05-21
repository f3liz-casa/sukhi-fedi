// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Locks in the EmojiReact translator's payload shape: a custom-emoji
// reaction on a note, addressed at the note author by the delivery
// Outbox.Consumer. The `content` field carries the emoji.

import { test, expect } from "bun:test";
import { handleBuildEmojiReact } from "./emoji_react.ts";

const ACTOR = "https://watch.example/users/alice";
const NOTE = "https://remote.example/notes/abc";

test("EmojiReact carries type, actor, object and the emoji content", async () => {
  const result = await handleBuildEmojiReact({
    actor: ACTOR,
    object: NOTE,
    content: "🦊",
    activityId: `${ACTOR}/reactions/1`,
    recipientInboxes: ["https://remote.example/users/bob/inbox"],
  });

  const react = result.emojiReact as Record<string, unknown>;
  expect(react["type"]).toBe("EmojiReact");
  expect(react["actor"]).toBe(ACTOR);
  expect(react["object"]).toBe(NOTE);
  expect(react["content"]).toBe("🦊");
});

test("EmojiReact accepts a :shortcode: custom emoji", async () => {
  const result = await handleBuildEmojiReact({
    actor: ACTOR,
    object: NOTE,
    content: ":blobcat:",
    activityId: `${ACTOR}/reactions/2`,
    recipientInboxes: [],
  });

  const react = result.emojiReact as Record<string, unknown>;
  expect(react["content"]).toBe(":blobcat:");
});

test("EmojiReact passes recipientInboxes through verbatim", async () => {
  const inboxes = ["https://remote.example/users/bob/inbox"];
  const result = await handleBuildEmojiReact({
    actor: ACTOR,
    object: NOTE,
    content: "👍",
    activityId: `${ACTOR}/reactions/3`,
    recipientInboxes: inboxes,
  });

  expect(result.recipientInboxes).toEqual(inboxes);
});
