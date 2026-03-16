/**
 * Misskey Flavored Markdown (MFM) to HTML converter.
 * Supports a subset of MFM commonly used in Misskey notes.
 */

export function mfmToHtml(mfm: string): string {
  let html = escapeHtml(mfm);

  // Block: code block ```lang\n...\n```
  html = html.replace(
    /```([^\n]*)\n([\s\S]*?)```/g,
    (_m, lang, code) =>
      `<pre><code${lang ? ` class="language-${escapeHtml(lang.trim())}"` : ""}>${code}</code></pre>`,
  );

  // Inline: `code`
  html = html.replace(/`([^`]+)`/g, (_m, code) => `<code>${code}</code>`);

  // MFM function: $[fn content] — render as styled span
  html = html.replace(
    /\$\[(\w+)(?:\.\w+(?:=\S+)?)* ([^\]]+)\]/g,
    (_m, fn, content) => `<span data-mfm="${fn}">${content}</span>`,
  );

  // Bold: **text**
  html = html.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");

  // Italic: *text* or _text_
  html = html.replace(/\*([^*]+)\*/g, "<em>$1</em>");
  html = html.replace(/_([^_]+)_/g, "<em>$1</em>");

  // Strikethrough: ~~text~~
  html = html.replace(/~~([^~]+)~~/g, "<del>$1</del>");

  // Small: <small>text</small> (MFM passthrough)
  html = html.replace(/&lt;small&gt;([\s\S]*?)&lt;\/small&gt;/g, "<small>$1</small>");

  // Inline emoji: :emoji_name:
  html = html.replace(
    /:([a-zA-Z0-9_]+):/g,
    (_m, name) =>
      `<span class="emoji" data-emoji="${name}">:${name}:</span>`,
  );

  // Mention: @user@host or @user
  html = html.replace(
    /@([a-zA-Z0-9_.-]+)@([a-zA-Z0-9.-]+)/g,
    (_m, user, host) =>
      `<a href="https://${host}/@${user}" class="mention">@${user}@${host}</a>`,
  );
  html = html.replace(
    /(?<![/@\w])@([a-zA-Z0-9_]+)/g,
    (_m, user) => `<a href="/@${user}" class="mention">@${user}</a>`,
  );

  // Hashtag: #tag
  html = html.replace(
    /(?<![&\w])#([a-zA-Z0-9_]+)/g,
    (_m, tag) => `<a href="/tags/${tag}" class="hashtag">#${tag}</a>`,
  );

  // URL: plain URLs
  html = html.replace(
    /(?<![="'])https?:\/\/[^\s<>"]+/g,
    (url) => `<a href="${url}">${url}</a>`,
  );

  // Newlines to <br>
  html = html.replace(/\n/g, "<br>");

  return html;
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}
