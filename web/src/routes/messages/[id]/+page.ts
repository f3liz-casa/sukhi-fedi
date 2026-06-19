// この個別スレッドだけ prerender を切る。中身は SPA 側で fetch するため
// ssr も切ったままで OK。adapter-static の fallback (200.html) が動的 :id を捌く。
export const prerender = false;
export const ssr = false;
