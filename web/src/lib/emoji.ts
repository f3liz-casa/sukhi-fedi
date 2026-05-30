// Swap Mastodon `:shortcode:` tokens for the custom-emoji images the
// server advertises in a status/account `emojis` array. Misskey and
// Mastodon both send these; without the substitution a remote name, bio
// or post shows the literal `:blobcat:`.

import type { Emoji } from './api';

// `html` is assumed to already be safe — server-rendered status/bio HTML,
// or text that went through `phrase()`. We only inject our own <img> and
// escape the url/shortcode we put into attributes.
export function renderEmojis(html: string, emojis?: Emoji[] | null): string {
  if (!html || !emojis || emojis.length === 0) return html;

  let out = html;
  for (const e of emojis) {
    if (!e.shortcode || !e.url) continue;
    const token = `:${e.shortcode}:`;
    if (!out.includes(token)) continue;

    const src = escapeAttr(e.url);
    const alt = escapeAttr(token);
    const img = `<img class="custom-emoji" src="${src}" alt="${alt}" title="${alt}" loading="lazy" />`;
    out = out.split(token).join(img);
  }
  return out;
}

function escapeAttr(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}
