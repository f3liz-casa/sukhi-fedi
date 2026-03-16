import { handleBuildNoteCw, handleBuildNoteHashtag, handleBuildNoteEmoji, handleBuildActor, handleBuildMove, handleBuildNoteMedia } from "./mastodon/mod.ts";
import { handleBuildBoost } from "./boost.ts";
import { handleBuildQuote } from "./quote.ts";

type Subscriber = (subject: string, handler: (payload: unknown) => Promise<unknown>) => Promise<void>;

/**
 * Registers all Mastodon-specific NATS subject handlers via the provided subscribe function.
 */
export function registerMastodonHandlers(subscribe: Subscriber): Promise<void>[] {
  return [
    subscribe("ap.build.boost", handleBuildBoost as (payload: unknown) => Promise<unknown>),
    subscribe("ap.build.note_cw", handleBuildNoteCw as (payload: unknown) => Promise<unknown>),
    subscribe("ap.build.note_hashtag", handleBuildNoteHashtag as (payload: unknown) => Promise<unknown>),
    subscribe("ap.build.note_emoji", handleBuildNoteEmoji as (payload: unknown) => Promise<unknown>),
    subscribe("ap.build.actor", handleBuildActor as (payload: unknown) => Promise<unknown>),
    subscribe("ap.build.move", handleBuildMove as (payload: unknown) => Promise<unknown>),
    subscribe("ap.build.note_media", handleBuildNoteMedia as (payload: unknown) => Promise<unknown>),
    subscribe("ap.build.mastodon_quote", handleBuildQuote as (payload: unknown) => Promise<unknown>),
  ];
}
