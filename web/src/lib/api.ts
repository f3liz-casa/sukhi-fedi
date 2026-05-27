import { loadToken, clearToken } from './auth';

export type Account = {
  id: string;
  username: string;
  acct: string;
  display_name: string;
  avatar: string | null;
  url: string;
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

export type Status = {
  id: string;
  created_at: string;
  content: string;
  spoiler_text?: string;
  sensitive?: boolean;
  account: Account;
  media_attachments: MediaAttachment[];
  tags: Tag[];
  url?: string;
};

export type TimelineKind = 'home' | 'public' | 'tag';

type FetchOpts = {
  auth?: boolean;
};

async function get(path: string, opts: FetchOpts = {}): Promise<Response> {
  const headers: Record<string, string> = { accept: 'application/json' };
  if (opts.auth !== false) {
    const t = loadToken();
    if (t) headers.authorization = `Bearer ${t.access_token}`;
  }
  return fetch(path, { headers });
}

function parseLinkMaxId(link: string | null): string | null {
  if (!link) return null;
  // Link: <https://…?max_id=42>; rel="next", <…>; rel="prev"
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

  if (res.status === 401 && needsAuth) {
    clearToken();
    throw new Error('unauthorized');
  }

  if (!res.ok) {
    throw new Error(`timeline_failed_${res.status}`);
  }

  const items = (await res.json()) as Status[];
  const nextMaxId = parseLinkMaxId(res.headers.get('link'));
  return { items, nextMaxId };
}
