import { Create, Note, Question } from "@fedify/fedify";
import { signAndSerialize } from "../../fedify/utils.ts";

export interface PollChoice {
  name: string;
  votes?: number;
}

export interface BuildPollPayload {
  actor: string;
  content: string;
  choices: PollChoice[];
  multiple: boolean;
  endTime?: string; // ISO 8601
  noteId: string;
  activityId: string;
  recipientInboxes: string[];
}

export interface BuildPollResult {
  poll: unknown;
  recipientInboxes: string[];
}

export async function handleBuildPoll(
  payload: BuildPollPayload,
): Promise<BuildPollResult> {
  const choiceNotes = payload.choices.map(
    (c) => new Note({ name: c.name }),
  );
  const questionInit: Record<string, unknown> = {
    id: new URL(payload.noteId),
    attribution: new URL(payload.actor),
    content: payload.content,
    published: Temporal.Now.instant(),
  };
  if (payload.multiple) {
    questionInit.anyOf = choiceNotes;
  } else {
    questionInit.oneOf = choiceNotes;
  }
  if (payload.endTime) {
    questionInit.endTime = Temporal.Instant.from(payload.endTime);
  }
  const question = new Question(questionInit);
  const create = new Create({
    id: new URL(payload.activityId),
    actor: new URL(payload.actor),
    object: question,
  });
  const pollJson = await signAndSerialize(payload.actor, create) as Record<string, unknown>;
  // Inject _misskey_votes per-choice vote counts
  const hasVotes = payload.choices.some((c) => c.votes !== undefined);
  if (hasVotes && pollJson["object"] && typeof pollJson["object"] === "object") {
    (pollJson["object"] as Record<string, unknown>)["_misskey_votes"] =
      payload.choices.map((c) => c.votes ?? 0);
  }
  return {
    poll: pollJson,
    recipientInboxes: payload.recipientInboxes,
  };
}
