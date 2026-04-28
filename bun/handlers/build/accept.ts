import { Accept, Follow } from "@fedify/fedify";
import { signAndSerialize } from "../../fedify/utils.ts";

export interface BuildAcceptPayload {
  actor: string;
  followActivityId: string;
  followActor: string;
  activityId: string;
}

export interface BuildAcceptResult {
  accept: unknown;
}

export async function handleBuildAccept(
  payload: BuildAcceptPayload,
): Promise<BuildAcceptResult> {
  const followObject = new Follow({
    id: new URL(payload.followActivityId),
    actor: new URL(payload.followActor),
    object: new URL(payload.actor),
  });

  const accept = new Accept({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: followObject,
  });

  const acceptJson = await signAndSerialize(payload.actor, accept);

  return { accept: acceptJson };
}
