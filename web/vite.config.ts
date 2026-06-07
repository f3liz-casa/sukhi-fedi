import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

// /login と /settings/password は GET=SPA ページ・POST=バックエンド、と
// メソッドで持ち主が分かれる。dev プロキシは path 単位なので、GET は
// bypass で SvelteKit に返し、POST(資格情報・パスワード)だけ :4000 へ送る。
const getToSpa = (req: { method?: string; url?: string }) =>
  req.method === 'GET' ? req.url : undefined;

export default defineConfig({
  plugins: [sveltekit()],
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://localhost:4000',
      '/oauth': 'http://localhost:4000',
      '/login': { target: 'http://localhost:4000', bypass: getToSpa },
      '/settings/password': { target: 'http://localhost:4000', bypass: getToSpa },
      '/logout': 'http://localhost:4000',
      '/.well-known': 'http://localhost:4000'
    }
  }
});
