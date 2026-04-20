import { Person } from "@fedify/fedify";
import { serialize, injectDefined } from "../../../fedify/utils.ts";

export interface BuildMisskeyActorPayload {
  actor: string;
  isCat?: boolean;
  missSummary?: string;
  followedMessage?: string;
  requireSigninToViewContents?: boolean;
  makeNotesFollowersOnlyBefore?: string | null;
  makeNotesHiddenBefore?: string | null;
}

export interface BuildMisskeyActorResult {
  actor: unknown;
}

export async function handleBuildMisskeyActor(
  payload: BuildMisskeyActorPayload,
): Promise<BuildMisskeyActorResult> {
  const person = new Person({
    id: new URL(payload.actor),
  });
  const actorJson = await serialize(person) as Record<string, unknown>;
  injectDefined(actorJson, {
    isCat: payload.isCat,
    _misskey_summary: payload.missSummary,
    _misskey_followedMessage: payload.followedMessage,
    _misskey_requireSigninToViewContents: payload.requireSigninToViewContents,
    _misskey_makeNotesFollowersOnlyBefore: payload.makeNotesFollowersOnlyBefore,
    _misskey_makeNotesHiddenBefore: payload.makeNotesHiddenBefore,
  });
  return { actor: actorJson };
}
