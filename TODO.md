# TODO

Surface for work still missing. Done items have been pruned —
`git log` is the diary, this file is the punch-list.

Design-deferred items (where to go *next* depends on which way we
turn) live in [`OPEN_QUESTIONS.md`](OPEN_QUESTIONS.md). The two
files are complementary: TODO is "do this", OPEN_QUESTIONS is
"decide this".

---

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
Shares the existing contexts; only the view layer differs. The planned
endpoint surface is mapped out in [`docs/MISSKEY_API.md`](docs/MISSKEY_API.md).

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

## Admin frontend (work in progress — paused mid-implementation)

Server-rendered HTML admin UI for the gateway. Stack chosen: **htmx +
Plug.Router + EEx** (not Phoenix LiveView — Phoenix/Endpoint isn't in
this codebase, the infra delta would dwarf the admin code). Auth: paste
a Mastodon OAuth bearer token, server verifies via
`SukhiFedi.OAuth.verify_bearer/1`, requires `account.is_admin = true`,
session-cookie persists the bearer. Resume from "what's done" below.

### Done already in this branch (deployed to sukhi.f3liz.casa)
- Watcher routes (`/`, `/api/watchers`, `/api/nodeinfo`,
  `/api/stats/stream`) gated on `:nodeinfo_monitor` addon; Kamal env
  sets `DISABLE_ADDONS=nodeinfo_monitor`. Real-SNS deploy returns 404
  on those paths.
- Kamal `config/deploy.yml` has per-service memory + cpu options
  sized to 2 vCPU / 12 GiB.
- All moderation business logic already exists:
  `SukhiFedi.Addons.Moderation.{suspend_account/3, unsuspend_account/2,
  list_reports/2, resolve_report/2, list_instance_blocks/1,
  block_instance/4, unblock_instance/2}`.

### Open decisions (already made, recorded so resume is straight)
- Cookie session signing key: **new `SECRET_KEY_BASE` env var** (not
  reused from `ERLANG_COOKIE`). Generate `openssl rand -hex 64`.
- Bootstrap admin token: **standard Mastodon OAuth flow** — admin
  obtains a bearer via any Mastodon client / API call, then pastes
  into `/admin/login`. No redirect-bounce OAuth UI yet.
- Stack: htmx (via CDN) + Plug.Router + EEx. No Phoenix, no SPA build.

### To do, in order

1. **Env plumbing for `SECRET_KEY_BASE`.**
   - `elixir/config/runtime.exs`: read it (`fetch_env!` in prod), store
     as `config :sukhi_fedi, :secret_key_base, ...`.
   - `.env.example`, `.kamal/secrets.example`, `docs/ENV.md`: add it
     with generation command and "must be stable across deploys —
     rotating invalidates every admin session" caveat.
   - `config/deploy.yml`: add `SECRET_KEY_BASE` to gateway `env.secret`.
   - `.kamal/secrets` (gitignored, local): paste actual value.

2. **`/admin` router infra.**
   - `elixir/lib/sukhi_fedi/web/admin/render.ex`: helper around
     `EEx.eval_file/2` rooted at `priv/admin_templates/`, returns
     iodata. Layout wrapping helper.
   - `elixir/lib/sukhi_fedi/web/admin/auth_plug.ex`: reads bearer from
     session cookie, calls `verify_bearer`, requires `is_admin`. 302 to
     `/admin/login` on miss. Assigns `:admin` to conn.
   - `elixir/lib/sukhi_fedi/web/admin/router.ex`: a `use Plug.Router`.
     Pipeline: `put_secret_key_base` → `Plug.Session` (cookie store,
     `_sukhi_admin` key, signing salt) → `fetch_session` → for
     non-`/login` routes also `AuthPlug`.
   - `elixir/lib/sukhi_fedi/web/router.ex`: `forward "/admin", to:
     SukhiFedi.Web.Admin.Router`.

3. **Login + dashboard pages.**
   - `priv/admin_templates/_layout.html.eex`: shell w/ nav (Users,
     Reports, Federation), htmx via `https://unpkg.com/htmx.org@2`.
     Minimal inline CSS or single small stylesheet — admin tool, not
     marketing.
   - `priv/admin_templates/login.html.eex`: paste-token form (POST
     `/admin/login`).
   - Controller in `admin/router.ex` for `POST /admin/login`: take
     `token`, run `verify_bearer`, require `is_admin`, store the raw
     token in session, redirect to `/admin`. `DELETE /admin/logout`
     clears session.
   - `priv/admin_templates/dashboard.html.eex`: counts (users,
     pending reports, instance blocks), recent activity.

4. **Users page.**
   - `users_controller.ex`: list (paginated), search by username/domain,
     `POST /admin/users/:id/suspend` / `unsuspend` returns the table
     row fragment (htmx swap-target).
   - Templates: `users/index.html.eex`, `users/_row.html.eex`.

5. **Reports queue.**
   - `reports_controller.ex`: list by status (open/resolved), resolve
     button hits `POST /admin/reports/:id/resolve` → row fragment swap.
   - Templates: `reports/index.html.eex`, `reports/_row.html.eex`.

6. **Domain (instance) blocks.**
   - `instance_blocks_controller.ex`: list, add (form), remove.
     Severity = silence | suspend.
   - Templates: `instance_blocks/index.html.eex`, `instance_blocks/_form.html.eex`.

### Deferred to a follow-up PR
- **Instance settings page.** Requires new `instance_settings` table
  (single-row k/v) since `INSTANCE_TITLE` is env-only today. Migration
  + Cachex layer + the admin form.
- **Automated OAuth bounce login** (`/admin/login` redirects to
  `/oauth/authorize`, callback exchanges code). Currently admin pastes
  a token. Fine for v1.
- **Audit log.** `who-did-what-when` for admin actions. Out of scope
  initially; revisit when there's more than one admin.

### Schemas to lean on (no migrations needed for steps 1–6)
- `accounts`: `is_admin`, `suspended_at`, `suspended_by_id`,
  `suspension_reason`, `domain`. Local users = `domain IS NULL`.
- `reports`: `account_id`, `target_id`, `note_id`, `comment`, `status`,
  `resolved_at`, `resolved_by_id`.
- `instance_blocks`: `domain`, `severity`, `reason`, `created_by_id`.
- `oauth_access_tokens`: lookup via `SukhiFedi.OAuth.verify_bearer/1`.

### Resume command
```
# In a fresh session, point Claude at the admin TODO and start step 1:
git status
# Then ask: "TODO.md の Admin frontend のステップ 1 から実装再開"
```
