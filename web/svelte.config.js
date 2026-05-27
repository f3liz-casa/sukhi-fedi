import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

// SSG single-page mode: every client route resolves to `index.html`, the
// SvelteKit runtime then renders the right page. The Elixir gateway is
// taught explicitly which paths (`/`, `/signup`, `/timeline`,
// `/app/callback`) should reach the SPA shell; everything else stays
// owned by the server (login, OAuth, AP, admin).
const config = {
  preprocess: vitePreprocess(),
  kit: {
    adapter: adapter({
      fallback: 'index.html',
      precompress: false,
      strict: false
    }),
    paths: {
      base: '',
      relative: false
    },
    // SvelteKit が `/_app/version.json` を pollInterval 毎に取りに
    // いって、ビルドの version 文字列が変わったら `$updated.current`
    // が true になる。+layout.svelte の UpdateBanner がそれを見て
    // 「新しい版が来ました、リロードしますか?」を出す。
    // 60s は「読んでいる人にうるさすぎず、置き去りにもしない」
    // 中間。
    version: {
      pollInterval: 60_000
    }
  }
};

export default config;
