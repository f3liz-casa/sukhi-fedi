// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Regression tests for the 887afb9f bug: Create(Note) shipped without
// to/cc, and iceshrimp/Mastodon dropped the note from timelines. These
// tests assert the activity *and* the inner Note both carry the
// expected audience shape. Run on every PR.

import { test, expect } from "bun:test";
import { handleBuildNote } from "./note.ts";
import { containsPublic, containsFollowers, testCreds } from "./_test_helpers.ts";

const ACTOR = "https://watch.example/users/alice";

test("Create(Note) addresses Public on `to` and followers on `cc` — activity", async () => {
  const result = await handleBuildNote({
    ...await testCreds(ACTOR),
    actor: ACTOR,
    content: "hi",
    recipientInboxes: [],
    noteId: `${ACTOR}/notes/1`,
    activityId: `${ACTOR}/activities/create/1`,
  });

  const json = result.note as Record<string, unknown>;
  expect(containsPublic(json["to"])).toBe(true);
  expect(containsFollowers(json["cc"], ACTOR)).toBe(true);
});

test("Create(Note) addresses Public on `to` and followers on `cc` — inner Note object", async () => {
  const result = await handleBuildNote({
    ...await testCreds(ACTOR),
    actor: ACTOR,
    content: "hi",
    recipientInboxes: [],
    noteId: `${ACTOR}/notes/2`,
    activityId: `${ACTOR}/activities/create/2`,
  });

  const json = result.note as Record<string, unknown>;
  const inner = json["object"] as Record<string, unknown>;
  expect(containsPublic(inner["to"])).toBe(true);
  expect(containsFollowers(inner["cc"], ACTOR)).toBe(true);
});

test("Create(Note) includes _misskey_content on the inner Note", async () => {
  const result = await handleBuildNote({
    ...await testCreds(ACTOR),
    actor: ACTOR,
    content: "hello <b>world</b>",
    recipientInboxes: [],
    noteId: `${ACTOR}/notes/3`,
    activityId: `${ACTOR}/activities/create/3`,
  });
  const inner = (result.note as Record<string, unknown>)["object"] as Record<string, unknown>;
  expect(inner["_misskey_content"]).toBe("hello <b>world</b>");
});

test("Create(Note) carries quoteUrl + _misskey_quote when a quote is set", async () => {
  const QUOTED = "https://remote.example/notes/orig";
  const result = await handleBuildNote({
    ...await testCreds(ACTOR),
    actor: ACTOR,
    content: "quoting",
    recipientInboxes: [],
    noteId: `${ACTOR}/notes/4`,
    activityId: `${ACTOR}/activities/create/4`,
    quoteUrl: QUOTED,
  });
  const inner = (result.note as Record<string, unknown>)["object"] as Record<string, unknown>;
  expect(inner["quoteUrl"]).toBe(QUOTED);
  expect(inner["_misskey_quote"]).toBe(QUOTED);
});

test("Create(Note) omits quote fields when there is no quote", async () => {
  const result = await handleBuildNote({
    ...await testCreds(ACTOR),
    actor: ACTOR,
    content: "no quote",
    recipientInboxes: [],
    noteId: `${ACTOR}/notes/5`,
    activityId: `${ACTOR}/activities/create/5`,
  });
  const inner = (result.note as Record<string, unknown>)["object"] as Record<string, unknown>;
  expect(inner["quoteUrl"]).toBeUndefined();
});
