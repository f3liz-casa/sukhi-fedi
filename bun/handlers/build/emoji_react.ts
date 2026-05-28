// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Builds an `EmojiReact` activity — a Misskey custom-emoji reaction on
// a note. Symmetric with `build/like.ts`; the only extra field is
// `content`, which carries the emoji (a unicode glyph or a
// `:shortcode:`).

import { EmojiReact } from "@fedify/fedify/vocab";
import { nowInstant } from "../../fedify/temporal.ts";
import { signAndSerialize, type SignedPayload } from "../../fedify/utils.ts";

export interface BuildEmojiReactPayload extends SignedPayload {
  actor: string;
  object: string;
  // The reaction emoji: a unicode glyph or a `:shortcode:`.
  content: string;
  activityId: string;
  recipientInboxes: string[];
}

export interface BuildEmojiReactResult {
  emojiReact: unknown;
  recipientInboxes: string[];
}

export async function handleBuildEmojiReact(
  payload: BuildEmojiReactPayload,
): Promise<BuildEmojiReactResult> {
  const react = new EmojiReact({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: new URL(payload.object),
    content: payload.content,
    published: nowInstant(),
  });

  const emojiReactJson = await signAndSerialize(payload, react);

  return {
    emojiReact: emojiReactJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
