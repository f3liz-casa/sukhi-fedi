// Swap Mastodon `:shortcode:` tokens for the custom-emoji images the
// server advertises in a status/account `emojis` array. Misskey and
// Mastodon both send these; without the substitution a remote name, bio
// or post shows the literal `:blobcat:`.

import type { Emoji } from './api';
import twemoji from '@twemoji/api';

// Self-hosted Twemoji (copied into static/twemoji/svg at build). Pointing the
// parser here keeps unicode emoji consistent across platforms without a CDN.
const TWEMOJI_OPTS = { base: '/twemoji/', folder: 'svg', ext: '.svg', className: 'twemoji' };

// `html` is assumed to already be safe — server-rendered status/bio HTML,
// or text that went through `phrase()`. We only inject our own <img> and
// escape the url/shortcode we put into attributes.
export function renderEmojis(html: string, emojis?: Emoji[] | null): string {
  if (!html) return html;

  let out = html;
  for (const e of emojis ?? []) {
    if (!e.shortcode || !e.url) continue;
    const token = `:${e.shortcode}:`;
    if (!out.includes(token)) continue;

    const src = escapeAttr(e.url);
    const alt = escapeAttr(token);
    const img = `<img class="custom-emoji" src="${src}" alt="${alt}" title="${alt}" loading="lazy" />`;
    out = out.split(token).join(img);
  }

  // Then unicode emoji → Twemoji images. Custom-emoji <img> we just inserted
  // carry no unicode, so they're left alone.
  return twemoji.parse(out, TWEMOJI_OPTS);
}

// The self-hosted URL for a single emoji char — for fixed UI icons (boost,
// favourite, …) rendered outside the HTML-content path. Let the parser pick
// the canonical filename so the FE0F variation selector, ZWJ sequences and
// keycaps resolve the same way they do in content.
export function twemojiUrl(emoji: string): string {
  const m = twemoji.parse(emoji, TWEMOJI_OPTS).match(/src="([^"]+)"/);
  return m ? m[1] : '';
}

function escapeAttr(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}
