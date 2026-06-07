// account_id → その人が入っている *exclusive* な Circle のタイトル列。
//
// タイムラインやアカウント行で、名前の横に「サークルの印」を出すための、
// ちいさなストア。ログイン時に一度だけ getLists + getListAccounts で集め、
// メンバーの出し入れがあったら refresh する。失敗してもバッジが出ない
// だけで、害はない。
//
// バッジは「ホームに出さない」= exclusive なサークルだけに付ける。ふつうの
// リスト(ホームにも流れる)は印を出さない——「これは、たまに会う人」という
// 合図にしたいから。

import { writable } from 'svelte/store';
import { getLists, getListAccounts } from './api';
import { isLoggedIn } from './auth';

export const circleTitles = writable<Record<string, string[]>>({});

let started = false;

export async function refreshCircles(): Promise<void> {
  if (!isLoggedIn()) return;
  try {
    const lists = await getLists();
    const map: Record<string, string[]> = {};

    for (const c of lists) {
      // exclusive なサークルだけがバッジの対象。
      if (!c.exclusive) continue;
      const accounts = await getListAccounts(c.id);
      for (const a of accounts) (map[a.id] ??= []).push(c.title);
    }

    circleTitles.set(map);
  } catch {
    // バッジが出ないだけ。タイムラインの表示は止めない。
  }
}

// 最初にバッジが必要になったとき、一度だけ読む。二重起動は防ぐ。
export function ensureCircles(): void {
  if (started) return;
  started = true;
  void refreshCircles();
}
