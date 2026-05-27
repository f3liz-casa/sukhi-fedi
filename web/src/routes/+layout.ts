// Static SSG: no per-route data loaders, no SSR, no prerender for
// dynamic content. The whole app is one prerendered shell that hydrates
// on the client.
export const prerender = true;
export const ssr = false;
