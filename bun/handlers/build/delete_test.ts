// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Regression for be3aa82: Delete(Note) missed to/cc and receivers left
// ghost notes on timelines. Asserts public addressing is on the Delete
// activity.

import { test, expect } from "bun:test";
import { handleBuildDelete } from "./delete.ts";
import { containsPublic, containsFollowers } from "./_test_helpers.ts";

const ACTOR = "https://watch.example/users/alice";

test("Delete(Note) addresses Public on `to` and followers on `cc`", async () => {
  const result = await handleBuildDelete({
    actor: ACTOR,
    activityId: `${ACTOR}/activities/delete/1`,
    objectId: `${ACTOR}/notes/1`,
    recipientInboxes: [],
  });

  const json = result.delete as Record<string, unknown>;
  expect(containsPublic(json["to"])).toBe(true);
  expect(containsFollowers(json["cc"], ACTOR)).toBe(true);
});
