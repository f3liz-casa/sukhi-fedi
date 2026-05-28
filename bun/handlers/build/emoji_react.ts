// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Builds a `Like` activity carrying a Misskey-style emoji reaction.
// The reaction emoji is on the `content` field; for custom emoji,
// a matching `Emoji` entry is attached via `tags` with the icon URL.
//
// Why `Like` instead of `EmojiReact`: recent Misskey + Sharkey send
// Like-with-content; Mastodon understands plain Like and silently
// ignores the content. EmojiReact (Pleroma's idiom) gets quarantined
// by Mastodon. One activity that round-trips through both worlds.
//
// File name kept for translator routing — `delivery/.../consumer.ex`
// dispatches `"emoji_react"` to this handler.

import { Like, Emoji, Image } from "@fedify/fedify/vocab";
import { nowInstant } from "../../fedify/temporal.ts";
import { signAndSerialize, type SignedPayload } from "../../fedify/utils.ts";

export interface BuildEmojiReactPayload extends SignedPayload {
  actor: string;
  object: string;
  // The reaction emoji: a unicode glyph or a `:shortcode:`.
  content: string;
  // Optional custom emoji metadata for the `tag` array. Only set when
  // `content` is a shortcode; unicode reactions leave this undefined.
  tag?: {
    name: string;
    url: string;
    static_url?: string | null;
  };
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
  const like = new Like({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: new URL(payload.object),
    content: payload.content,
    tags: payload.tag ? [emojiTag(payload.tag)] : [],
    published: nowInstant(),
  });

  const likeJson = await signAndSerialize(payload, like);

  // Return key stays `emojiReact` to keep delivery payload routing
  // unchanged. Wire type is Like; outer shape is the same envelope.
  return {
    emojiReact: likeJson,
    recipientInboxes: payload.recipientInboxes,
  };
}

function emojiTag(tag: NonNullable<BuildEmojiReactPayload["tag"]>): Emoji {
  return new Emoji({
    name: tag.name,
    icon: new Image({ url: new URL(tag.url) }),
  });
}
