import { loadToken, clearToken } from './auth';

export type Field = {
  name: string;
  value: string;
  verified_at?: string | null;
};

export type Emoji = {
  shortcode: string;
  url: string;
  static_url?: string;
  visible_in_picker?: boolean;
};

export type Account = {
  id: string;
  username: string;
  acct: string;
  display_name: string;
  emojis?: Emoji[];
  avatar: string | null;
  avatar_static?: string | null;
  header?: string | null;
  header_static?: string | null;
  url: string;
  note?: string;
  locked?: boolean;
  bot?: boolean;
  created_at?: string;
  followers_count?: number;
  following_count?: number;
  statuses_count?: number;
  fields?: Field[];
  // verify_credentials だけが返す。admin は { name: "admin", ... }。
  // 管理ページへの入口を出すかどうかの判定に使う。
  role?: { id: string; name: string; permissions: string } | null;
};

export type MediaAttachment = {
  id: string;
  type: string;
  url: string;
  preview_url?: string | null;
  description?: string | null;
};

export type Tag = {
  name: string;
  url: string;
};

export type Visibility = 'public' | 'unlisted' | 'private' | 'direct';

export type Status = {
  id: string;
  created_at: string;
  content: string;
  emojis?: Emoji[];
  spoiler_text?: string;
  sensitive?: boolean;
  visibility?: Visibility;
  in_reply_to_id?: string | null;
  in_reply_to_account_id?: string | null;
  account: Account;
  // Fedibird-compatible quote post, nested one level deep (no further).
  quote?: Status | null;
  // Boost (reblog): the boosted status, nested one level deep. Present only
  // on the wrapper status whose `account` is the booster.
  reblog?: Status | null;
  media_attachments: MediaAttachment[];
  tags: Tag[];
  url?: string;
  reactions?: Reaction[];
  favourited?: boolean;
  favourites_count?: number;
  reblogged?: boolean;
  reblogs_count?: number;
  bookmarked?: boolean;
  pinned?: boolean;
  poll?: Poll | null;
};

export type PollOption = {
  title: string;
  votes_count?: number | null;
};

export type Poll = {
  id: string;
  expires_at?: string | null;
  expired: boolean;
  multiple: boolean;
  votes_count: number;
  voters_count?: number | null;
  options: PollOption[];
  emojis?: Emoji[];
  voted?: boolean;
  own_votes?: number[];
};

export type Reaction = {
  name: string;
  count: number;
  me: boolean;
  url?: string | null;
  static_url?: string | null;
};

export type Relationship = {
  id: string;
  following: boolean;
  followed_by: boolean;
  requested: boolean;
  blocking?: boolean;
  muting?: boolean;
};

export type TimelineKind = 'home' | 'public' | 'tag';

type FetchOpts = {
  auth?: boolean;
};

function authHeader(): Record<string, string> {
  const t = loadToken();
  return t ? { authorization: `Bearer ${t.access_token}` } : {};
}

async function get(path: string, opts: FetchOpts = {}): Promise<Response> {
  const headers: Record<string, string> = { accept: 'application/json' };
  if (opts.auth !== false) Object.assign(headers, authHeader());
  return fetch(path, { headers });
}

async function sendJson(method: string, path: string, body: unknown): Promise<Response> {
  return fetch(path, {
    method,
    headers: {
      accept: 'application/json',
      'content-type': 'application/json',
      ...authHeader()
    },
    body: JSON.stringify(body)
  });
}

async function sendForm(method: string, path: string, form: FormData): Promise<Response> {
  return fetch(path, {
    method,
    headers: { accept: 'application/json', ...authHeader() },
    body: form
  });
}

function failOn401(res: Response): void {
  if (res.status === 401) {
    clearToken();
    throw new Error('unauthorized');
  }
}

function parseLinkMaxId(link: string | null): string | null {
  if (!link) return null;
  for (const part of link.split(',')) {
    const m = part.match(/<([^>]+)>;\s*rel="next"/);
    if (m) {
      try {
        const u = new URL(m[1]);
        return u.searchParams.get('max_id');
      } catch {
        return null;
      }
    }
  }
  return null;
}

export type Page<T> = {
  items: T[];
  nextMaxId: string | null;
};

// ── timelines ────────────────────────────────────────────────────────

export async function fetchTimeline(
  kind: TimelineKind,
  opts: { tag?: string; maxId?: string | null; limit?: number } = {}
): Promise<Page<Status>> {
  const limit = opts.limit ?? 20;
  const qs = new URLSearchParams();
  qs.set('limit', String(limit));
  if (opts.maxId) qs.set('max_id', opts.maxId);

  let path: string;
  let needsAuth = false;
  switch (kind) {
    case 'home':
      path = `/api/v1/timelines/home?${qs}`;
      needsAuth = true;
      break;
    case 'public':
      qs.set('local', '1');
      path = `/api/v1/timelines/public?${qs}`;
      break;
    case 'tag':
      if (!opts.tag) throw new Error('tag required');
      path = `/api/v1/timelines/tag/${encodeURIComponent(opts.tag)}?${qs}`;
      break;
  }

  const res = await get(path, { auth: needsAuth });
  if (needsAuth) failOn401(res);
  if (!res.ok) throw new Error(`timeline_failed_${res.status}`);

  const items = (await res.json()) as Status[];
  const nextMaxId = parseLinkMaxId(res.headers.get('link'));
  return { items, nextMaxId };
}

// ── conversations (DM) ───────────────────────────────────────────────

export type Conversation = {
  id: string;
  unread: boolean;
  accounts: Account[];
  last_status: Status | null;
};

export async function getConversations(
  opts: { maxId?: string | null; limit?: number } = {}
): Promise<Page<Conversation>> {
  const qs = new URLSearchParams();
  qs.set('limit', String(opts.limit ?? 20));
  if (opts.maxId) qs.set('max_id', opts.maxId);

  const res = await get(`/api/v1/conversations?${qs}`);
  failOn401(res);
  if (!res.ok) throw new Error(`conversations_failed_${res.status}`);

  const items = (await res.json()) as Conversation[];
  return { items, nextMaxId: parseLinkMaxId(res.headers.get('link')) };
}

export async function markConversationRead(id: string): Promise<Conversation> {
  const res = await sendJson('POST', `/api/v1/conversations/${encodeURIComponent(id)}/read`, {});
  failOn401(res);
  if (!res.ok) throw new Error(`conversation_read_failed_${res.status}`);
  return (await res.json()) as Conversation;
}

// ── statuses ─────────────────────────────────────────────────────────

export type ComposeInput = {
  status: string;
  spoiler_text?: string;
  sensitive?: boolean;
  visibility?: Visibility;
  in_reply_to_id?: string | null;
  media_ids?: string[];
};

export async function postStatus(input: ComposeInput): Promise<Status> {
  // null / undefined / 空配列をそぎ落として送る。送らないことが
  // 「サーバ既定」を意味する API なので、こちらで余計なキーを入れない。
  const body: Record<string, unknown> = { status: input.status };
  if (input.spoiler_text) body.spoiler_text = input.spoiler_text;
  if (input.sensitive) body.sensitive = true;
  if (input.visibility) body.visibility = input.visibility;
  if (input.in_reply_to_id) body.in_reply_to_id = input.in_reply_to_id;
  if (input.media_ids && input.media_ids.length > 0) body.media_ids = input.media_ids;

  const res = await sendJson('POST', '/api/v1/statuses', body);
  failOn401(res);
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err?.error ?? `post_failed_${res.status}`);
  }
  return (await res.json()) as Status;
}

// ── interactions ─────────────────────────────────────────────────────

async function sendNoBody(method: string, path: string): Promise<Response> {
  return fetch(path, {
    method,
    headers: { accept: 'application/json', ...authHeader() }
  });
}

export async function favourite(statusId: string): Promise<Status> {
  return statusAction('POST', `/api/v1/statuses/${encodeURIComponent(statusId)}/favourite`);
}

export async function unfavourite(statusId: string): Promise<Status> {
  return statusAction('POST', `/api/v1/statuses/${encodeURIComponent(statusId)}/unfavourite`);
}

export async function reblog(statusId: string): Promise<Status> {
  return statusAction('POST', `/api/v1/statuses/${encodeURIComponent(statusId)}/reblog`);
}

export async function unreblog(statusId: string): Promise<Status> {
  return statusAction('POST', `/api/v1/statuses/${encodeURIComponent(statusId)}/unreblog`);
}

export async function bookmark(statusId: string): Promise<Status> {
  return statusAction('POST', `/api/v1/statuses/${encodeURIComponent(statusId)}/bookmark`);
}

export async function unbookmark(statusId: string): Promise<Status> {
  return statusAction('POST', `/api/v1/statuses/${encodeURIComponent(statusId)}/unbookmark`);
}

export async function react(statusId: string, emoji: string): Promise<Status> {
  return statusAction(
    'PUT',
    `/api/v1/sukhi/statuses/${encodeURIComponent(statusId)}/react/${encodeURIComponent(emoji)}`
  );
}

export async function unreact(statusId: string, emoji: string): Promise<Status> {
  return statusAction(
    'DELETE',
    `/api/v1/sukhi/statuses/${encodeURIComponent(statusId)}/react/${encodeURIComponent(emoji)}`
  );
}

async function statusAction(method: string, path: string): Promise<Status> {
  const res = await sendNoBody(method, path);
  failOn401(res);
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err?.error ?? `action_failed_${res.status}`);
  }
  return (await res.json()) as Status;
}

// Delete one of your own notes. The gateway enforces ownership (a
// non-owner gets 403); the deleted Status JSON Mastodon returns is
// unused, so resolve void.
export async function deleteStatus(statusId: string): Promise<void> {
  const res = await sendNoBody('DELETE', `/api/v1/statuses/${encodeURIComponent(statusId)}`);
  failOn401(res);
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err?.error ?? `delete_failed_${res.status}`);
  }
}

export async function getBookmarks(
  opts: { maxId?: string | null; limit?: number } = {}
): Promise<Page<Status>> {
  const qs = new URLSearchParams();
  qs.set('limit', String(opts.limit ?? 20));
  if (opts.maxId) qs.set('max_id', opts.maxId);

  const res = await get(`/api/v1/bookmarks?${qs}`);
  failOn401(res);
  if (!res.ok) throw new Error(`bookmarks_failed_${res.status}`);
  const items = (await res.json()) as Status[];
  return { items, nextMaxId: parseLinkMaxId(res.headers.get('link')) };
}

// ── polls ────────────────────────────────────────────────────────────

// choices は選んだ選択肢の index 配列。single choice の投票でも配列で送る
// のが Mastodon の仕様。返ってくるのは最新の集計を載せた Poll。
export async function votePoll(pollId: string, choices: number[]): Promise<Poll> {
  const res = await sendJson('POST', `/api/v1/polls/${encodeURIComponent(pollId)}/votes`, {
    choices: choices.map(String)
  });
  failOn401(res);
  if (!res.ok) throw new Error(`vote_failed_${res.status}`);
  return (await res.json()) as Poll;
}

// ── media ────────────────────────────────────────────────────────────

export async function uploadMedia(file: File, description?: string): Promise<MediaAttachment> {
  const fd = new FormData();
  fd.set('file', file);
  if (description) fd.set('description', description);
  // v1 は同期で返す。v2 は処理中なら 202 を返して
  // /api/v1/media/:id で polling、というのが Mastodon の仕様。
  // 最初は v1 のシンプルさを取る。重い変換が要るときは server 側で
  // 設定するか、別途 v2 にスイッチ。
  const res = await sendForm('POST', '/api/v1/media', fd);
  failOn401(res);
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err?.error ?? `media_failed_${res.status}`);
  }
  return (await res.json()) as MediaAttachment;
}

// ── accounts: self ───────────────────────────────────────────────────

export async function verifyCredentials(): Promise<Account> {
  const res = await get('/api/v1/accounts/verify_credentials');
  failOn401(res);
  if (!res.ok) throw new Error(`verify_failed_${res.status}`);
  return (await res.json()) as Account;
}

// Memoised id of the logged-in account, for "is this mine?" UI checks
// (e.g. whether to offer delete on a status). Resolves null when logged
// out or on a lookup miss; cached so a timeline of N statuses costs one
// verify_credentials call, not N.
let meIdPromise: Promise<string | null> | null = null;

export function currentAccountId(): Promise<string | null> {
  if (!loadToken()) return Promise.resolve(null);

  if (!meIdPromise) {
    meIdPromise = verifyCredentials()
      .then((a) => a.id)
      .catch(() => {
        meIdPromise = null; // let a later call retry after a transient failure
        return null;
      });
  }

  return meIdPromise;
}

export type CredentialsUpdate = {
  display_name?: string;
  note?: string;
  avatar?: File | null;
  header?: File | null;
  locked?: boolean;
};

export async function updateCredentials(input: CredentialsUpdate): Promise<Account> {
  const fd = new FormData();
  if (input.display_name !== undefined) fd.set('display_name', input.display_name);
  if (input.note !== undefined) fd.set('note', input.note);
  if (input.locked !== undefined) fd.set('locked', input.locked ? 'true' : 'false');
  if (input.avatar) fd.set('avatar', input.avatar);
  if (input.header) fd.set('header', input.header);

  const res = await sendForm('PATCH', '/api/v1/accounts/update_credentials', fd);
  failOn401(res);
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err?.error ?? `update_failed_${res.status}`);
  }
  return (await res.json()) as Account;
}

// ── accounts: lookup / show ──────────────────────────────────────────

export async function lookupAccount(acct: string): Promise<Account> {
  const qs = new URLSearchParams({ acct });
  const res = await get(`/api/v1/accounts/lookup?${qs}`, { auth: false });
  if (res.status === 404) throw new Error('not_found');
  if (!res.ok) throw new Error(`lookup_failed_${res.status}`);
  return (await res.json()) as Account;
}

export async function getAccount(id: string): Promise<Account> {
  const res = await get(`/api/v1/accounts/${encodeURIComponent(id)}`, { auth: false });
  if (res.status === 404) throw new Error('not_found');
  if (!res.ok) throw new Error(`account_failed_${res.status}`);
  return (await res.json()) as Account;
}

export async function getAccountStatuses(
  id: string,
  opts: { maxId?: string | null; limit?: number } = {}
): Promise<Page<Status>> {
  const qs = new URLSearchParams();
  qs.set('limit', String(opts.limit ?? 20));
  if (opts.maxId) qs.set('max_id', opts.maxId);

  const res = await get(`/api/v1/accounts/${encodeURIComponent(id)}/statuses?${qs}`, {
    auth: false
  });
  if (!res.ok) throw new Error(`account_statuses_failed_${res.status}`);
  const items = (await res.json()) as Status[];
  return { items, nextMaxId: parseLinkMaxId(res.headers.get('link')) };
}

export async function getStatus(id: string): Promise<Status> {
  const res = await get(`/api/v1/statuses/${encodeURIComponent(id)}`, { auth: false });
  if (res.status === 404) throw new Error('not_found');
  if (!res.ok) throw new Error(`status_failed_${res.status}`);
  return (await res.json()) as Status;
}

export type Context = { ancestors: Status[]; descendants: Status[] };

export async function getContext(id: string): Promise<Context> {
  const res = await get(`/api/v1/statuses/${encodeURIComponent(id)}/context`, { auth: false });
  if (!res.ok) throw new Error(`context_failed_${res.status}`);
  return (await res.json()) as Context;
}

async function fetchAccountList(
  endpoint: 'followers' | 'following',
  id: string,
  opts: { maxId?: string | null; limit?: number } = {}
): Promise<Page<Account>> {
  const qs = new URLSearchParams();
  qs.set('limit', String(opts.limit ?? 40));
  if (opts.maxId) qs.set('max_id', opts.maxId);
  const res = await get(
    `/api/v1/accounts/${encodeURIComponent(id)}/${endpoint}?${qs}`,
    { auth: false }
  );
  if (!res.ok) throw new Error(`${endpoint}_failed_${res.status}`);
  const items = (await res.json()) as Account[];
  return { items, nextMaxId: parseLinkMaxId(res.headers.get('link')) };
}

export const getAccountFollowers = (id: string, opts?: { maxId?: string | null; limit?: number }) =>
  fetchAccountList('followers', id, opts);

export const getAccountFollowing = (id: string, opts?: { maxId?: string | null; limit?: number }) =>
  fetchAccountList('following', id, opts);

// ── follows ──────────────────────────────────────────────────────────

export async function getRelationships(ids: string[]): Promise<Relationship[]> {
  if (ids.length === 0) return [];
  const qs = new URLSearchParams();
  for (const id of ids) qs.append('id[]', id);
  const res = await get(`/api/v1/accounts/relationships?${qs}`);
  failOn401(res);
  if (!res.ok) throw new Error(`relationships_failed_${res.status}`);
  return (await res.json()) as Relationship[];
}

export async function followAccount(id: string): Promise<Relationship> {
  const res = await sendJson('POST', `/api/v1/accounts/${encodeURIComponent(id)}/follow`, {});
  failOn401(res);
  if (!res.ok) throw new Error(`follow_failed_${res.status}`);
  return (await res.json()) as Relationship;
}

export async function unfollowAccount(id: string): Promise<Relationship> {
  const res = await sendJson('POST', `/api/v1/accounts/${encodeURIComponent(id)}/unfollow`, {});
  failOn401(res);
  if (!res.ok) throw new Error(`unfollow_failed_${res.status}`);
  return (await res.json()) as Relationship;
}

// ── search ───────────────────────────────────────────────────────────

export type SearchResult = {
  accounts: Account[];
  hashtags: Tag[];
  statuses: Status[];
};

// resolve=true は WebFinger で remote actor を取りにいく(初フォロー
// の前段)。auth 必須。q 未入力なら空結果を返して silent に no-op。
export async function searchAll(
  q: string,
  opts: { resolve?: boolean; limit?: number; type?: 'accounts' | 'hashtags' | 'statuses' } = {}
): Promise<SearchResult> {
  const trimmed = q.trim();
  if (!trimmed) return { accounts: [], hashtags: [], statuses: [] };

  const qs = new URLSearchParams();
  qs.set('q', trimmed);
  if (opts.resolve) qs.set('resolve', 'true');
  if (opts.limit) qs.set('limit', String(opts.limit));
  if (opts.type) qs.set('type', opts.type);

  const res = await get(`/api/v2/search?${qs}`);
  failOn401(res);
  if (!res.ok) throw new Error(`search_failed_${res.status}`);
  return (await res.json()) as SearchResult;
}

// ── notifications ────────────────────────────────────────────────────

export type NotificationType =
  | 'favourite'
  | 'reblog'
  | 'follow'
  | 'follow_request'
  | 'mention'
  | 'status'
  | 'poll'
  | 'update'
  // Sukhi 拡張のリアクション通知。サーバが未対応でも型として許す。
  | 'reaction';

export type Notification = {
  id: string;
  type: NotificationType;
  created_at: string;
  account: Account;
  status?: Status | null;
};

export async function getNotifications(
  opts: { maxId?: string | null; limit?: number } = {}
): Promise<Page<Notification>> {
  const qs = new URLSearchParams();
  qs.set('limit', String(opts.limit ?? 30));
  if (opts.maxId) qs.set('max_id', opts.maxId);

  const res = await get(`/api/v1/notifications?${qs}`);
  failOn401(res);
  if (!res.ok) throw new Error(`notifications_failed_${res.status}`);
  const items = (await res.json()) as Notification[];
  return { items, nextMaxId: parseLinkMaxId(res.headers.get('link')) };
}

export async function dismissNotification(id: string): Promise<void> {
  const res = await sendJson('POST', `/api/v1/notifications/${encodeURIComponent(id)}/dismiss`, {});
  failOn401(res);
  if (!res.ok) throw new Error(`dismiss_failed_${res.status}`);
}

export async function clearNotifications(): Promise<void> {
  const res = await sendJson('POST', '/api/v1/notifications/clear', {});
  failOn401(res);
  if (!res.ok) throw new Error(`clear_failed_${res.status}`);
}

// ── moderation: block / mute ─────────────────────────────────────────
// block/unblock/mute/unmute はどれも更新後の Relationship を返す。

function relAction(method: string, path: string): Promise<Relationship> {
  return sendJson(method, path, {}).then(async (res) => {
    failOn401(res);
    if (!res.ok) throw new Error(`rel_action_failed_${res.status}`);
    return (await res.json()) as Relationship;
  });
}

export const blockAccount = (id: string) =>
  relAction('POST', `/api/v1/accounts/${encodeURIComponent(id)}/block`);
export const unblockAccount = (id: string) =>
  relAction('POST', `/api/v1/accounts/${encodeURIComponent(id)}/unblock`);
export const muteAccount = (id: string) =>
  relAction('POST', `/api/v1/accounts/${encodeURIComponent(id)}/mute`);
export const unmuteAccount = (id: string) =>
  relAction('POST', `/api/v1/accounts/${encodeURIComponent(id)}/unmute`);
