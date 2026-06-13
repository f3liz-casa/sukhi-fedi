<script lang="ts">
  import type { Status } from '$lib/api';
  import Self from './Status.svelte';
  import Avatar from './Avatar.svelte';
  import CircleBadge from './CircleBadge.svelte';
  import StatusActions from './StatusActions.svelte';
  import StatusMedia from './StatusMedia.svelte';
  import StatusPoll from './StatusPoll.svelte';
  import Twemoji from './Twemoji.svelte';
  import { renderEmojis } from '$lib/emoji';
  import { phrase } from '$lib/phrase';
  import { t, locale, type Locale, type TranslationKey } from '$lib/i18n';

  let {
    status,
    // 返信ボタンを出すか。タイムラインでは true、プロフィール一覧では false
    // など、置き場ごとに切り替えたい。
    canReply = false,
    onreply,
    onupdate,
    ondelete
  }: {
    status: Status;
    canReply?: boolean;
    onreply?: (s: Status) => void;
    onupdate?: (s: Status) => void;
    // 自分のノートを削除したとき。置き場ごとに一覧から外したい。
    ondelete?: (s: Status) => void;
  } = $props();

  // Display name falls back to username when servers omit it (Misskey
  // sometimes does for fresh actors).
  let name = $derived(status.account.display_name || status.account.username);
  let avatar = $derived(status.account.avatar || null);
  let ts = $derived(formatTime(status.created_at, $t, $locale));

  // CW（spoiler）を開いているか。閉じている間は本文だけでなく添付も隠す。
  let cwOpen = $state(false);

  function formatTime(
    iso: string,
    tr: (key: TranslationKey, params?: Record<string, string | number>) => string,
    loc: Locale
  ): string {
    try {
      const d = new Date(iso);
      const now = Date.now();
      const diff = (now - d.getTime()) / 1000;
      if (diff < 60) return tr('status.now');
      if (diff < 3600) return tr('status.minutesAgo', { n: Math.floor(diff / 60) });
      if (diff < 86_400) return tr('status.hoursAgo', { n: Math.floor(diff / 3600) });
      if (diff < 86_400 * 7) return tr('status.daysAgo', { n: Math.floor(diff / 86_400) });
      return d.toLocaleDateString(loc === 'ko' ? 'ko-KR' : 'ja-JP');
    } catch {
      return iso;
    }
  }
</script>

{#if status.reblog}
  <!-- ブースト: 上に「○○がブースト」を出し、中身は元の status をそのまま描く。
       返信・ブースト等のアクションは入れ子側（本物のノート）に効く。 -->
  <div class="boost">
    <a class="boost-by" href={`/@${status.account.acct}`}>
      <Twemoji emoji="🔁" /> {@html renderEmojis(phrase(name), status.account.emojis)} {$t('status.boostedBy')}
    </a>
    <Self status={status.reblog} {canReply} {onreply} {onupdate} {ondelete} />
  </div>
{:else}
<article class="status">
  <Avatar class="avatar" src={avatar} {name} />

  <div class="body">
    <header class="meta">
      <a class="display-name" href={`/@${status.account.acct}`}
        >{@html renderEmojis(phrase(name), status.account.emojis)}</a
      >
      <CircleBadge accountId={status.account.id} />
      <a href={`/@${status.account.acct}`}>@{status.account.acct}</a>
      <span>·</span>
      <a class="timestamp" href={`/@${status.account.acct}/${status.id}`} title={status.created_at}>{ts}</a>
    </header>

    {#if status.spoiler_text}
      <details bind:open={cwOpen}>
        <summary>{status.spoiler_text}</summary>
        <div class="content">{@html renderEmojis(status.content, status.emojis)}</div>
      </details>
    {:else}
      <div class="content">{@html renderEmojis(status.content, status.emojis)}</div>
    {/if}

    {#if status.quote}
      <a class="quote-card" href={`/@${status.quote.account.acct}/${status.quote.id}`}>
        <div class="quote-head">
          <Avatar
            class="quote-avatar"
            src={status.quote.account.avatar}
            name={status.quote.account.display_name || status.quote.account.username}
          />
          <span class="quote-name"
            >{@html renderEmojis(
              phrase(status.quote.account.display_name || status.quote.account.username),
              status.quote.account.emojis
            )}</span
          >
          <span class="quote-acct">@{status.quote.account.acct}</span>
        </div>
        <div class="quote-content">{@html renderEmojis(status.quote.content, status.quote.emojis)}</div>
      </a>
    {/if}

    {#if (!status.spoiler_text || cwOpen) && status.media_attachments.length > 0}
      <!-- CW 付きは cwOpen で隠す。CW 無しの sensitive はぼかして「見る」を出す
           （二重に隠さないよう spoiler のときはブラーを掛けない）。 -->
      <StatusMedia
        attachments={status.media_attachments}
        blur={status.sensitive && !status.spoiler_text}
      />
    {/if}

    {#if status.poll}
      <StatusPoll poll={status.poll} />
    {/if}

    <StatusActions {status} {canReply} {onreply} {onupdate} {ondelete} />
  </div>
</article>
{/if}

<style>
  .boost-by {
    display: block;
    padding: 0.25rem 1rem 0;
    font-size: 0.8rem;
    color: var(--color-text-muted);
    text-decoration: none;
  }

  .boost-by:hover {
    text-decoration: underline;
  }

  .quote-card {
    display: block;
    margin-top: 0.5rem;
    padding: 0.5rem 0.75rem;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    text-decoration: none;
    color: inherit;
  }
  .quote-card:hover {
    background: var(--fill-soft);
  }
  .quote-head {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    margin-bottom: 0.25rem;
    font-size: var(--text-sm);
  }
  .quote-name {
    font-weight: 600;
  }
  .quote-acct {
    color: var(--color-text-muted);
  }
  .quote-content {
    font-size: var(--text-sm);
  }
</style>
