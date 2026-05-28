import { Announce } from "@fedify/fedify/vocab";
import { nowInstant } from "../../fedify/temporal.ts";
import { signAndSerialize, type SignedPayload } from "../../fedify/utils.ts";
import { resolveAudience } from "../../fedify/addressing.ts";

export interface BuildAnnouncePayload extends SignedPayload {
  actor: string;
  object: string;
  activityId: string;
  recipientInboxes: string[];
}

export interface BuildAnnounceResult {
  announce: unknown;
  recipientInboxes: string[];
}

export async function handleBuildAnnounce(
  payload: BuildAnnouncePayload,
): Promise<BuildAnnounceResult> {
  const audience = resolveAudience({ kind: "public", actor: payload.actor });

  const announce = new Announce({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: new URL(payload.object),
    published: nowInstant(),
    tos: audience.tos,
    ccs: audience.ccs,
  });

  const announceJson = await signAndSerialize(payload, announce);

  return {
    announce: announceJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
