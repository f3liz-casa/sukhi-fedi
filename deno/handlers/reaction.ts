// SPDX-License-Identifier: MPL-2.0
import type { Activity, Object as APObject } from "npm:@fedify/fedify";

export interface ReactionInstruction {
  actor_id: number;
  note_id: number;
  emoji: string;
}

export async function buildReaction(
  instruction: ReactionInstruction,
  domain: string
): Promise<Activity> {
  const actorUri = `https://${domain}/users/${instruction.actor_id}`;
  const noteUri = `https://${domain}/notes/${instruction.note_id}`;
  const reactionId = `https://${domain}/reactions/${crypto.randomUUID()}`;

  return {
    "@context": "https://www.w3.org/ns/activitystreams",
    type: "EmojiReact",
    id: reactionId,
    actor: actorUri,
    object: noteUri,
    content: instruction.emoji,
    tag: instruction.emoji.startsWith(":") ? {
      type: "Emoji",
      name: instruction.emoji,
    } : undefined,
  };
}

export async function handleReactionActivity(
  activity: Activity,
  nc: any
): Promise<void> {
  if (activity.type !== "EmojiReact" && activity.type !== "Like") return;

  const emoji = activity.type === "EmojiReact" 
    ? (activity as any).content || "❤️"
    : "❤️";

  const instruction = {
    type: "store_reaction",
    actor_uri: typeof activity.actor === "string" ? activity.actor : activity.actor?.id,
    object_uri: typeof activity.object === "string" ? activity.object : (activity.object as APObject)?.id,
    emoji,
    ap_id: activity.id,
  };

  await nc.publish("elixir.inbox", JSON.stringify(instruction));
}
