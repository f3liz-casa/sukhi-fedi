// 動的セグメント (id) はビルド時のクロールでは見つからないので、この
// ルートだけ prerender を切る。中身は SPA 側で fetch するため ssr も切る。
// プロフィール (@[acct]) と同じ扱い。adapter-static の fallback が起動する。
export const prerender = false;
export const ssr = false;
