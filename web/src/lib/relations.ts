// アカウント一覧 (followers / following) を取って、ログイン時は
// relationships を一発で引いて並べる。followers/following ページが
// 同じ形でしか違わないので、共通ヘルパに切り出している。

import {
  getAccountFollowers,
  getAccountFollowing,
  getRelationships,
  verifyCredentials,
  type Account,
  type Page,
  type Relationship
} from './api';
import { isLoggedIn } from './auth';

export type AccountKind = 'followers' | 'following';

export type AccountListPage = {
  page: Page<Account>;
  // account.id → relationship。自分自身の id は除外して引く。
  relations: Map<string, Relationship>;
  meId: string | null;
};

export async function loadAccountList(
  kind: AccountKind,
  accountId: string,
  opts: { maxId?: string | null } = {}
): Promise<AccountListPage> {
  const fetcher = kind === 'followers' ? getAccountFollowers : getAccountFollowing;
  const page = await fetcher(accountId, opts);

  let meId: string | null = null;
  const relations = new Map<string, Relationship>();

  if (isLoggedIn() && page.items.length > 0) {
    try {
      const me = await verifyCredentials();
      meId = me.id;
      const ids = page.items.map((a) => a.id).filter((id) => id !== meId);
      if (ids.length > 0) {
        const rs = await getRelationships(ids);
        for (const r of rs) relations.set(r.id, r);
      }
    } catch {
      // 取れなくても一覧は出す。フォローボタンが出ないだけ。
    }
  }

  return { page, relations, meId };
}
