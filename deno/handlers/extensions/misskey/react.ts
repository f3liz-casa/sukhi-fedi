import { EmojiReact } from "@fedify/fedify";
import { signAndSerialize } from "../../fedify/utils.ts";

export interface BuildReactPayload {
  actor: string;
  object: string;
  activityId: string;
  emoji: string;
}

export interface BuildReactResult {
  react: unknown;
}

export async function handleBuildReact(
  payload: BuildReactPayload,
): Promise<BuildReactResult> {
  const react = new EmojiReact({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: new URL(payload.object),
    content: payload.emoji,
  });
  return { react: await signAndSerialize(payload.actor, react) };
}
