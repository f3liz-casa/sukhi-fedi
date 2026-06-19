// 書きかけのノートを、この端末に覚えておく。ナビゲーションや
// リロードで消えてしまわないように。
//
//   sf.compose_draft — { text, spoiler, useSpoiler, sensitive, visibility }
//
// media は覚えない。アップロード済みの id はサーバ側で期限切れ・
// GC されるので、戻しても切れた id を指すだけ ─ 文字だけ戻す。
// 返信の下書きは覚えない(トップの新規ノート専用)。保存も復元も
// 静かに ─ 「保存しました」のトーストもバッジも出さない。
import { browser } from '$app/environment';
import type { Visibility } from './api';

const DRAFT_KEY = 'sf.compose_draft';

export type ComposeDraft = {
  text: string;
  spoiler: string;
  useSpoiler: boolean;
  sensitive: boolean;
  visibility: Visibility;
};

export function saveComposeDraft(d: ComposeDraft): void {
  if (!browser) return;
  localStorage.setItem(DRAFT_KEY, JSON.stringify(d));
}

export function loadComposeDraft(): ComposeDraft | null {
  if (!browser) return null;
  const raw = localStorage.getItem(DRAFT_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as ComposeDraft;
  } catch {
    return null;
  }
}

export function clearComposeDraft(): void {
  if (!browser) return;
  localStorage.removeItem(DRAFT_KEY);
}
