import { Like } from "@fedify/fedify";
import { Temporal } from "@js-temporal/polyfill";
import { signAndSerialize } from "../../fedify/utils.ts";

export interface BuildLikePayload {
  actor: string;
  object: string;
  activityId: string;
  recipientInboxes: string[];
}

export interface BuildLikeResult {
  like: unknown;
  recipientInboxes: string[];
}

export async function handleBuildLike(
  payload: BuildLikePayload,
): Promise<BuildLikeResult> {
  const like = new Like({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: new URL(payload.object),
    published: Temporal.Now.instant(),
  });

  const likeJson = await signAndSerialize(payload.actor, like);

  return {
    like: likeJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
