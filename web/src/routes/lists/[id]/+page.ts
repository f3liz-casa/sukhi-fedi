// 動的セグメント (id) はビルド時にクロールでは見つからないので、
// この個別リストだけ prerender を切る。/lists 一覧は静的なまま、
// 個別リストは SPA 側で fetch する。adapter-static の fallback
// (index.html) が返るので、クライアントが起動して描画する。
export const prerender = false;
