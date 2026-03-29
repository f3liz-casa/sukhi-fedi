// SPDX-License-Identifier: MPL-2.0
import { Add, Remove } from "@fedify/fedify";
import { signAndSerialize } from "../../fedify/utils.ts";

export interface CollectionOpPayload {
  /** Local actor URI performing the operation. */
  actor: string;
  /** AP URI of the object being added/removed (e.g. note URI). */
  objectUri: string;
  /** AP URI of the target collection (e.g. featured collection URI). */
  targetUri: string;
  /** AP ID for the Add/Remove activity. */
  activityId: string;
  /** Remote inbox URLs to deliver the activity to. */
  recipientInboxes: string[];
}

export interface CollectionOpResult {
  activity: unknown;
  recipientInboxes: string[];
}

/** Build a signed Add activity for pinning a note to the featured collection. */
export async function handleBuildAdd(payload: CollectionOpPayload): Promise<CollectionOpResult> {
  const activity = new Add({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: new URL(payload.objectUri),
    target: new URL(payload.targetUri),
  });

  const activityJson = await signAndSerialize(payload.actor, activity);

  return {
    activity: activityJson,
    recipientInboxes: payload.recipientInboxes,
  };
}

/** Build a signed Remove activity for unpinning a note from the featured collection. */
export async function handleBuildRemove(payload: CollectionOpPayload): Promise<CollectionOpResult> {
  const activity = new Remove({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: new URL(payload.objectUri),
    target: new URL(payload.targetUri),
  });

  const activityJson = await signAndSerialize(payload.actor, activity);

  return {
    activity: activityJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
