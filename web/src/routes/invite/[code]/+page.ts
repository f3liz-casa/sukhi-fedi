// 動的セグメント (code) はビルド時にクロールでは見つからないので、
// この招待ページだけ prerender を切る。コードの中身は SPA 側で
// fetch する。adapter-static の fallback (index.html) が返るので、
// クライアントが起動して描画する。
export const prerender = false;
