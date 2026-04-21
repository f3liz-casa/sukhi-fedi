# TODO

Tracking surface for work the Mastodon-MVP push (PR1–PR5) deferred. Items are
grouped by where they sit in the architecture, not by priority — pick whatever
unblocks the next user-facing thing.

When you finish an item, delete it; this file is for what's *missing*, not for
what got done. Cross-link to the PR/issue that closes it if it helps.

---

## Federation completeness (delivery node + Bun)

- [ ] **JetStream durable consumer for `sns.outbox.>`.** Today `Outbox.Consumer`
      uses plain `Gnat.sub`, so the OUTBOX stream grows forever (no ACK). Wire a
      durable JetStream consumer with explicit ACK. Worker idempotency
      (`delivery_receipts`) already covers the at-least-once redelivery case.
- [ ] **`sns.outbox.actor.updated` translator.** Bun has the `actor` builder but
      no `Update(Actor)` wrapper. Add one and let `Outbox.Consumer` route
      `actor.updated` to it (currently `:skipped`).
- [ ] **`ActorFetcher` mirror on the delivery side.** Today inbox URL is derived
      by convention `<actor_uri>/inbox`. Mastodon and most software follow this,
      but spec-compliant resolution requires fetching the actor JSON for the
      `inbox` field. Mirror the gateway's `SukhiFedi.Federation.ActorFetcher`
      with an ETS cache.
- [ ] **Local-target follow auto-Accept.** When a local user follows another
      local user, `request_follow/2` writes a `Follow(state: pending)` and an
      outbox event — but no local Accept loop. Add an inbox-side shortcut so
      local follows go straight to `accepted` without the HTTP round-trip.
- [ ] **Inbound Create(Note) → write a `notes` row.** Currently
      `AP.Instructions` only stores raw JSON in `objects` (except for DMs).
      `SukhiFedi.Timelines` queries `notes` so remote content never appears in
      home/public timelines until a Note row exists for it. Either:
      (a) write a Note row alongside Object on inbound Create, or
      (b) switch Timelines to read Object too.
- [ ] **Reply to a remote note.** `Notes.create_status/2` only resolves
      `in_reply_to_id` against local Note ids. Replying to a remote thread
      needs the remote post mirrored locally first; either auto-mirror on
      lookup or surface a 404.
- [ ] **DM (`visibility: "direct"`) support.** `create_status/2` rejects direct
      visibility today. Needs mention extraction from content + addressing
      derivation; Bun's `dm` translator is already in place.

## Mastodon API surface (gaps after PR1–PR5/PR3.5)

- [ ] **Notifications.** `GET /api/v1/notifications`, `/:id`, `clear`, `dismiss`.
      Needs a `notifications` table (or Reaction/Boost/Follow scan) and an
      inbox-side path that creates rows on incoming Like/Announce/Follow.
- [ ] **Search.** `GET /api/v2/search` (q, type, account_id, …). Hashtag and
      account search are easy; status search needs a strategy (no full-text
      index in core schema yet).
- [ ] **Streaming WebSocket.** `/api/v1/streaming` (home, public, list, hashtag).
      Gateway needs a Bandit upgrade handler; the `Streaming` addon already has
      a NATS Registry / `stream.new_post` broadcast.
- [ ] **Web Push.** `POST /api/v1/push/subscription`, `GET`, `PUT`, `DELETE`.
      `WebPush` addon has the context; capability + VAPID key flow missing.
- [ ] **Polls REST.** `GET /api/v1/polls/:id`, `POST /:id/votes`. Tables
      (`Poll`, `PollOption`, `PollVote`) exist; capability missing. Also
      requires `create_status/2` to accept `poll[…]` params.
- [ ] **Lists.** `/api/v1/lists` CRUD + `/api/v1/timelines/list/:id`.
      No table yet.
- [ ] **Hashtag timelines.** `/api/v1/timelines/tag/:hashtag`. Needs tag
      extraction from content on note insert and a `note_tags` table.
- [ ] **Scheduled statuses.** `/api/v1/scheduled_statuses`. No table yet.
- [ ] **Conversations / threads.** `/api/v1/conversations`. Builds on
      `ConversationParticipant` (already a table).
- [ ] **Trends, suggestions, directory.** Optional but expected by some
      Mastodon clients; deprioritised.

## Mastodon API — moderation REST surface

The `Moderation` addon has the context; capabilities are missing.

- [ ] `POST /api/v1/accounts/:id/{block,unblock,mute,unmute}` + `GET /api/v1/{blocks,mutes}`
- [ ] `POST /api/v1/reports`
- [ ] `POST /api/v1/domain_blocks`, `GET`, `DELETE`
- [ ] Admin endpoints (`/api/admin/accounts`, `/api/admin/reports`, …) — addon
      capability with `addon: :admin_api` (new addon id).

## Misskey API native surface

The plan was always Mastodon-first → Misskey on the same machinery. The
infrastructure (OAuth, capability auth, view splitting) is ready.

- [ ] **Auth.** `/api/auth/session/generate`, `/api/auth/session/userkey`. Map
      Misskey's session-key flow onto the existing `oauth_access_tokens` table.
- [ ] **`/api/i`, `/api/i/update`** — Mastodon `verify_credentials` /
      `update_credentials` mirror, Misskey JSON shape.
- [ ] **`/api/users/show`, `/users/lookup`, `/users/notes`, `/users/{followers,following}`,
      `/users/{follow,unfollow}`** — the accounts surface in Misskey shape.
- [ ] **`/api/notes/{create,delete,show,timeline,local-timeline,global-timeline,
      hybrid-timeline,replies,mentions}`** — statuses + timelines in Misskey
      shape. Reuse `SukhiFedi.{Notes,Timelines}`; only the view layer differs.
- [ ] **`/api/notes/reactions/create`, `/notes/reactions/delete`** — Misskey
      uses non-default emojis (custom reactions). The `Reaction` table already
      supports arbitrary emoji strings.
- [ ] **`/api/notes/favorites/create`, `/notes/favorites/delete`,
      `/i/favorites`** — bookmarks-equivalent in Misskey naming.
- [ ] New view modules under `api/lib/sukhi_api/views/misskey_*.ex` (mirror of
      the `mastodon_*` set). Tag capabilities with `addon: :misskey_api`.
- [ ] Addon manifest on Bun side (`bun/addons/misskey_api/manifest.ts`) is
      currently a placeholder shell — extend with Misskey-flavoured
      translators if any are needed (custom reactions, soft-renotes).

## Operational / hardening

- [ ] **ETS bearer-token cache** in `SukhiApi` (60s TTL, keyed by token hash).
      Today every protected request synchronously RPCs `OAuth.verify_bearer/1`.
      Will matter once timelines are hot.
- [ ] **Drop legacy `accounts.token` column.** Grep callers first; emit
      a migration once nothing reads it.
- [ ] **Snowflake id migration.** Currently `MastodonAccount`/`MastodonStatus`
      serialize `Integer.to_string/1`. Wrap in `SukhiApi.Views.Id.encode/1`
      already done; flipping to snowflakes is a one-line change there + a
      bigserial→bigint migration on every PK column. Defer until peering at
      scale.
- [ ] **Presigned-URL media uploads (>8 MiB).** `MEDIA_DIR` server-side
      uploads cap at 8 MiB inline (distributed Erlang transport size). For
      large files, surface the existing
      `SukhiFedi.Addons.Media.generate_upload_url/3` over a new capability
      that returns `{upload_url, fields}`; client PUTs to S3 directly.
- [ ] **Rate-limit per-token** (in addition to the per-IP `RateLimitPlug`).
      Mastodon's published limits: 300 / 5 min for authenticated REST.

## Documentation / dev experience

- [ ] **Curl walkthrough** for the OAuth dance + post-status + media-upload
      flow as a runnable shell script under `scripts/smoke.sh`.
- [ ] **`MASTODON_API.md`** — table of supported endpoints + notes on
      Mastodon-spec deviations (e.g. id format, `direct` not yet supported).

## Tests

- [ ] Run integration suite green against `docker-compose.test.yml`. The
      tests under `elixir/test/integration/` have all been written but never
      run end-to-end against the test stack. Verify migrations apply cleanly
      and the DB-touching tests pass.
- [ ] Bun side: add tests that exercise the new translator payload shapes the
      delivery `Outbox.Consumer` constructs (`undo` with nested `Like` /
      `Follow`, `add`/`remove` for featured collection, …).

## Cleanup

- [ ] **Remove unused alias warning** in `Notes` for `Boost` reference once
      the favourite/reblog code path is landed (likely no longer needed after
      PR3.5; verify and drop).
- [ ] **Pre-existing warnings** in `lib/sukhi_fedi/web/nodeinfo_controller.ex`
      (`unused import Ecto.Query`) and `schema/poll_option.ex`
      (`invalid association :votes`) — unrelated to the Mastodon work but
      noisy; clean up.
