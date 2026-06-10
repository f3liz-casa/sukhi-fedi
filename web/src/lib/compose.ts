// ヘッダーの「書く」と、タイムラインの composer をつなぐ小さな合図。
// 押すたびに数が増え、タイムライン側は増えたのを見て composer を開き、
// 開いたら 0 に戻す。タイムライン以外のページからは、先に /timeline へ
// 移動してから鳴らす(AppNav 側)。
import { writable } from 'svelte/store';

export const composeRequest = writable(0);

export function requestCompose(): void {
  composeRequest.update((n) => n + 1);
}
