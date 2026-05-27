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
    }
  }
};

export default config;
