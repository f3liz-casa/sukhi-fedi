import { mfmToHtml, handleBuildReact, handleBuildPoll, handleBuildTalk, handleBuildMisskeyActor, handleBuildMisskeyEmoji } from "./misskey/mod.ts";
import { handleBuildQuote } from "./quote.ts";
import { handleBuildBoost } from "./boost.ts";

type Subscriber = (subject: string, handler: (payload: unknown) => Promise<unknown>) => Promise<void>;

/**
 * Registers all Misskey-specific NATS subject handlers via the provided subscribe function.
 */
export function registerMisskeyHandlers(subscribe: Subscriber): Promise<void>[] {
  return [
    subscribe("ap.build.react", handleBuildReact as (payload: unknown) => Promise<unknown>),
    subscribe("ap.mfm.to_html", (payload: unknown) => Promise.resolve({ html: mfmToHtml((payload as { mfm: string }).mfm) })),
    subscribe("ap.build.quote", handleBuildQuote as (payload: unknown) => Promise<unknown>),
    subscribe("ap.build.poll", handleBuildPoll as (payload: unknown) => Promise<unknown>),
    subscribe("ap.build.renote", handleBuildBoost as (payload: unknown) => Promise<unknown>),
    subscribe("ap.build.talk", handleBuildTalk as (payload: unknown) => Promise<unknown>),
    subscribe("ap.build.misskey_actor", handleBuildMisskeyActor as (payload: unknown) => Promise<unknown>),
    subscribe("ap.build.misskey_emoji", handleBuildMisskeyEmoji as (payload: unknown) => Promise<unknown>),
  ];
}
