import { Move, Person } from "@fedify/fedify";
import { serialize, signAndSerialize } from "../../../fedify/utils.ts";

export interface BuildActorPayload {
  actor: string;
  manuallyApprovesFollowers?: boolean;
  alsoKnownAs?: string[];
}

export interface BuildActorResult {
  actor: unknown;
}

export async function handleBuildActor(
  payload: BuildActorPayload,
): Promise<BuildActorResult> {
  const personInit: Record<string, unknown> = {
    id: new URL(payload.actor),
    manuallyApprovesFollowers: payload.manuallyApprovesFollowers ?? false,
  };
  if (payload.alsoKnownAs && payload.alsoKnownAs.length > 0) {
    personInit.aliases = payload.alsoKnownAs.map((u) => new URL(u));
  }
  const person = new Person(personInit);
  const actorJson = await serialize(person);
  return { actor: actorJson };
}

export interface BuildMovePayload {
  actor: string;
  movedTo: string;
  activityId: string;
  recipientInboxes: string[];
}

export interface BuildMoveResult {
  move: unknown;
  recipientInboxes: string[];
}

export async function handleBuildMove(
  payload: BuildMovePayload,
): Promise<BuildMoveResult> {
  const move = new Move({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: new URL(payload.actor),
    target: new URL(payload.movedTo),
  });
  return {
    move: await signAndSerialize(payload.actor, move),
    recipientInboxes: payload.recipientInboxes,
  };
}
