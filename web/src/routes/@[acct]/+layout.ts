// 動的セグメント (acct) はビルド時にクロールでは見つからないので、
// このサブツリーだけ prerender を切る。SPA 側で fetch するため
// ssr も切ったままで OK。adapter-static は fallback (200.html /
// index.html) を返してくれるので、クライアントが起動して描画する。
export const prerender = false;
export const ssr = false;
