import { Follow } from "@fedify/fedify/vocab";
import { signAndSerialize, type SignedPayload } from "../../fedify/utils.ts";

export interface BuildFollowPayload extends SignedPayload {
  actor: string;
  object: string;
  activityId: string;
}

export interface BuildFollowResult {
  follow: unknown;
}

export async function handleBuildFollow(
  payload: BuildFollowPayload,
): Promise<BuildFollowResult> {
  const follow = new Follow({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: new URL(payload.object),
  });

  const followJson = await signAndSerialize(payload, follow);

  return { follow: followJson };
}
