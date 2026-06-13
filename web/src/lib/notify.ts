// 通知の「性質」はぜんぶここに置く。
//
// 通知はふたつの層に分かれる:
//
//   direct  — mention(返信・DM)と follow_request。会話で、相手が
//             待っている。だから正直に: 数をそのまま出し、SSE で
//             届いた瞬間に増える。
//   ambient — favourite・reblog・follow など。嬉しいけれど、急ぎでは
//             ない。だから静かに: 数字を出さず、育つかたち
//             (NotifGlyph)で見せて、ページ遷移の境界でだけ更新する。
//             流れてきても画面の前では動かさない — 変化の瞬間を
//             誰も見ないことが「景色」の条件だから。
//
// 「どこまで見たか」は層ごとに localStorage で覚える(この端末の
// 景色は、この端末のもの)。通知ページの該当タブを開いたとき
// markSeen で進む。
import { writable } from 'svelte/store';
import { getNotifications, type Notification, type NotificationType } from './api';
import { loadToken } from './auth';

export type Tier = 'direct' | 'ambient';

export const DIRECT_TYPES: NotificationType[] = ['mention', 'follow_request'];

export function tierOf(type: NotificationType): Tier {
  return DIRECT_TYPES.includes(type) ? 'direct' : 'ambient';
}

// まだ見ていない数。AppNav がこれを描く。
export const directUnseen = writable(0);
export const ambientUnseen = writable(0);

const SEEN_KEY: Record<Tier, string> = {
  direct: 'sf.seen.direct',
  ambient: 'sf.seen.ambient'
};

// snowflake id は桁の違う十進文字列。長さ→辞書順で比べる。
function newerThan(id: string, seen: string): boolean {
  return id.length === seen.length ? id > seen : id.length > seen.length;
}

/**
 * 最新の一ページを取って、層ごとの未見数を数えなおす。
 * AppNav がページ遷移の境界で呼ぶ — ambient の表示が動くのは
 * ここだけ。初めての端末では「いま」を起点にする(過去の分で
 * いきなり木が立たないように)。
 */
export async function refreshUnseen(): Promise<void> {
  let items: Notification[];
  try {
    items = (await getNotifications({ limit: 40 })).items;
  } catch {
    // 取れなかったら、表示は前のまま。そっとしておく。
    return;
  }

  const counts: Record<Tier, number> = { direct: 0, ambient: 0 };
  const newest: Partial<Record<Tier, string>> = {};

  for (const n of items) {
    const tier = tierOf(n.type);
    newest[tier] ??= n.id;
    const seen = localStorage.getItem(SEEN_KEY[tier]);
    if (seen === null || newerThan(n.id, seen)) counts[tier]++;
  }

  for (const tier of ['direct', 'ambient'] as const) {
    const id = newest[tier];
    if (id && localStorage.getItem(SEEN_KEY[tier]) === null) {
      localStorage.setItem(SEEN_KEY[tier], id);
      counts[tier] = 0;
    }
  }

  directUnseen.set(counts.direct);
  ambientUnseen.set(counts.ambient);
}

/** 通知ページがタブを見せたとき。そこまでは見た、と覚えて数を戻す。 */
export function markSeen(tier: Tier, newestId?: string): void {
  if (newestId) localStorage.setItem(SEEN_KEY[tier], newestId);
  (tier === 'direct' ? directUnseen : ambientUnseen).set(0);
}

/** 「すべて消す」のあと。サーバ側が空なので、両方の数も空に。 */
export function clearCounts(): void {
  directUnseen.set(0);
  ambientUnseen.set(0);
}

// ── direct の SSE ────────────────────────────────────────────────────
// /api/v1/streaming/user/notification を一本だけ開いておく。
// EventSource は Authorization ヘッダを付けられない(token を URL に
// 出したくない)ので、fetch のストリームを自前で読む。
// direct だけがここで動く。ambient は流れてきても無視 — 次の遷移で
// refreshUnseen が数えなおすから、取りこぼしはない。

let streamAbort: AbortController | null = null;

export function startStream(): void {
  if (streamAbort) return;
  const ac = new AbortController();
  streamAbort = ac;
  void run(ac);
}

export function stopStream(): void {
  streamAbort?.abort();
  streamAbort = null;
}

async function run(ac: AbortController): Promise<void> {
  while (!ac.signal.aborted) {
    const t = loadToken();
    if (!t) break;

    try {
      const res = await fetch('/api/v1/streaming/user/notification', {
        headers: {
          accept: 'text/event-stream',
          authorization: `Bearer ${t.access_token}`
        },
        signal: ac.signal
      });
      // token が死んでいるなら叩き続けない。ログアウトは authed な
      // 通常リクエスト側が気づいて片づける。
      if (res.status === 401) break;
      if (!res.ok || !res.body) throw new Error(`stream_${res.status}`);
      await readEvents(res.body, ac.signal);
    } catch {
      // 切れたら下でひと呼吸おいて、つなぎなおす。
    }

    await sleep(30_000, ac.signal);
  }

  // break で出たとき(token 切れなど)、死んだ controller を握った
  // ままだと次の startStream が始められない。手を放しておく。
  if (streamAbort === ac) streamAbort = null;
}

// SSE の枠組みだけの小さな読み手。`event:` と `data:` を集めて、
// 空行で一フレーム。コメント行(ハートビート ":thump")は素通り。
async function readEvents(body: ReadableStream<Uint8Array>, signal: AbortSignal): Promise<void> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buf = '';
  let event = '';
  let data = '';

  for (;;) {
    const { done, value } = await reader.read();
    if (done || signal.aborted) return;
    buf += decoder.decode(value, { stream: true });

    let nl: number;
    while ((nl = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, nl).replace(/\r$/, '');
      buf = buf.slice(nl + 1);

      if (line === '') {
        if (event && data) onEvent(event, data);
        event = '';
        data = '';
      } else if (line.startsWith('event:')) {
        event = line.slice(6).trim();
      } else if (line.startsWith('data:')) {
        data += line.slice(5).trim();
      }
    }
  }
}

function onEvent(event: string, data: string): void {
  if (event !== 'notification') return;
  try {
    const n = JSON.parse(data) as Notification;
    if (tierOf(n.type) === 'direct') directUnseen.update((c) => c + 1);
  } catch {
    // 形がちがうフレームは、読めなかったことにする。
  }
}

function sleep(ms: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve) => {
    if (signal.aborted) return resolve();
    const id = setTimeout(resolve, ms);
    signal.addEventListener(
      'abort',
      () => {
        clearTimeout(id);
        resolve();
      },
      { once: true }
    );
  });
}
