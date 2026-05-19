# TODO

Surface for work still missing. Done items have been pruned —
`git log` is the diary, this file is the punch-list.

Design-deferred items (where to go *next* depends on which way we
turn) live in [`OPEN_QUESTIONS.md`](OPEN_QUESTIONS.md). The two
files are complementary: TODO is "do this", OPEN_QUESTIONS is
"decide this".

---

## Federation completeness

- [ ] **DM (`visibility: "direct"`) send path.** Bun's `dm`
      translator is in place and inbound DMs already mirror to a
      `notes` row plus `conversation_participants`. The missing
      half is `Notes.create_status/2` rejecting `"direct"` today;
      it needs mention extraction + addressing derivation.
      Strategy parked in [OPEN_QUESTIONS Q4](OPEN_QUESTIONS.md#q4-dm-visibility-direct--宛先解決).
- [ ] **`mention` notification type.** Trips when local users land
      in another note's address list. Falls out naturally from the
      DM work because we'll already be extracting mentions there.
- [ ] **Note-fetch HTTP signature.** `Federation.NoteFetcher` does
      an unsigned GET. Mastodon Secure Mode + Misskey auth-fetch-
      required servers reject those. The fetch path needs the same
      `signAs` plumbing the inbox already uses.

## Mastodon API surface — open

- [ ] **Streaming WebSocket** — see [OPEN_QUESTIONS Q2](OPEN_QUESTIONS.md#q2-streaming-websocket--どこに置くか).
- [ ] **Search (`/api/v2/search`)** — see [OPEN_QUESTIONS Q1](OPEN_QUESTIONS.md#q1-search-戦略--full-text-どうやるか).
- [ ] **Push delivery side.** `Addons.WebPush.send_notification/2`
      is still a stub; subscribe/get/put/delete REST is live, but
      no Notification → Push happens yet. Needs a push-web library
      + VAPID encryption. Pairs with an Oban worker that consumes
      notification rows and POSTs each subscription's
      encrypted-payload endpoint.
- [ ] **Scheduled statuses.** `/api/v1/scheduled_statuses` — no
      table yet. Same Multi+outbox pattern as `create_status`, with
      an Oban-scheduled `publish_at` worker.
- [ ] **Trends / suggestions / directory.** Optional surface;
      deprioritised.

## Misskey native API

Single addon `:misskey_api` (per [OPEN_QUESTIONS Q3](OPEN_QUESTIONS.md#q3-misskey-native-api--addon-マニフェストの粒度)).
Shares the existing contexts; only the view layer differs.

- [ ] **Auth.** `/api/auth/session/{generate,userkey}` — map
      Misskey's session-key flow onto `oauth_access_tokens`.
- [ ] **`/api/i`, `/api/i/update`** — mirror Mastodon's
      verify/update_credentials in Misskey shape.
- [ ] **`/api/users/*`** — `show`, `lookup`, `notes`,
      `{followers,following,follow,unfollow}`.
- [ ] **`/api/notes/*`** — `{create,delete,show,timeline,
      local-timeline,global-timeline,hybrid-timeline,replies,
      mentions}`.
- [ ] **`/api/notes/reactions/*`** — custom emoji reactions (table
      already supports arbitrary emoji strings).
- [ ] **`/api/notes/favorites/*`, `/i/favorites`** — bookmarks
      under Misskey naming.
- [ ] **`bun/addons/misskey_api/manifest.ts`** — currently a
      placeholder shell; extend if any translators are needed
      (custom reactions, soft-renotes).

## Admin REST

- [ ] **`/api/v1/admin/*`** — accounts, reports, domain_blocks.
      `SukhiFedi.Addons.Moderation` already has the writes (suspend,
      resolve_report, block_instance). New addon
      `:admin_api` (per [OPEN_QUESTIONS Q9](OPEN_QUESTIONS.md#q9-admin-rest--admin_api-を新-addon-にするか)) so
      admin can be toggled independently from user-facing
      block/mute/report.

## Operational / hardening

- [ ] **Presigned-URL media uploads (>8 MiB).** Inline POST caps at
      the distributed Erlang transport limit. Surface
      `SukhiFedi.Addons.Media.generate_upload_url/3` over a new
      capability that returns `{upload_url, fields}`. Design in
      [OPEN_QUESTIONS Q5](OPEN_QUESTIONS.md#q5-メディア-8-mib--presigned-url-の-capability-形).
