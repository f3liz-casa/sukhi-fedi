// 動的セグメント (tag) はビルド時のクロールでは見つからないので、
// このページだけ prerender を切る。adapter-static の fallback
// (index.html) が返り、クライアントが起動してタグ TL を fetch する。
export const prerender = false;
