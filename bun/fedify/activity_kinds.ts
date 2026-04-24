// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Table-driven dispatch for inbox Activity types. Replaces a 60-line
// if-else chain in handlers/inbox.ts. Keep Follow out of this table:
// it has a special return shape (save_and_reply with Accept).

import {
  Accept,
  type Activity,
  Add,
  Announce,
  Block,
  Create,
  Delete,
  EmojiReact,
  Flag,
  Like,
  Move,
  Reject,
  Remove,
  Undo,
  Update,
} from "@fedify/fedify";
import { cachedDocumentLoader } from "./context.ts";

export type GenericActivityKind =
  | "Announce"
  | "Create"
  | "Update"
  | "Delete"
  | "Like"
  | "EmojiReact"
  | "Undo"
  | "Accept"
  | "Reject"
  | "Move"
  | "Block"
  | "Flag"
  | "Add"
  | "Remove";

export type ActivityKind = GenericActivityKind | "Follow";

type ParseOpts = { documentLoader: typeof cachedDocumentLoader };
type Parser = (raw: Record<string, unknown>, opts: ParseOpts) => Promise<Activity>;

export const KIND_PARSERS: Record<GenericActivityKind, Parser> = {
  Announce: (raw, opts) => Announce.fromJsonLd(raw, opts),
  Create: (raw, opts) => Create.fromJsonLd(raw, opts),
  Update: (raw, opts) => Update.fromJsonLd(raw, opts),
  Delete: (raw, opts) => Delete.fromJsonLd(raw, opts),
  Like: (raw, opts) => Like.fromJsonLd(raw, opts),
  EmojiReact: (raw, opts) => EmojiReact.fromJsonLd(raw, opts),
  Undo: (raw, opts) => Undo.fromJsonLd(raw, opts),
  Accept: (raw, opts) => Accept.fromJsonLd(raw, opts),
  Reject: (raw, opts) => Reject.fromJsonLd(raw, opts),
  Move: (raw, opts) => Move.fromJsonLd(raw, opts),
  Block: (raw, opts) => Block.fromJsonLd(raw, opts),
  Flag: (raw, opts) => Flag.fromJsonLd(raw, opts),
  Add: (raw, opts) => Add.fromJsonLd(raw, opts),
  Remove: (raw, opts) => Remove.fromJsonLd(raw, opts),
};

export function classifyActivity(
  raw: Record<string, unknown>,
): ActivityKind | "unknown" {
  const t = raw["type"];
  if (typeof t !== "string") return "unknown";
  if (t === "Follow") return "Follow";
  if (t in KIND_PARSERS) return t as GenericActivityKind;
  return "unknown";
}
