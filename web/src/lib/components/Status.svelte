<script lang="ts">
  import { getAccountCached, type Status } from '$lib/api';
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
    // リーダーページ（記事ページ）では全文を出したいので、折りたたみを切る。
    full = false,
    onreply,
    onupdate,
    ondelete
  }: {
    status: Status;
    canReply?: boolean;
    full?: boolean;
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

  // 返信のとき、返信先の人を上に小さく示す。payload には相手の handle が
  // 無いので、in_reply_to_account_id からアカウントだけ遅延 fetch(共有
  // キャッシュ)で引く。取れるまでは名前なしの「返信」だけ静かに出す。
  let replyToAcct = $state<string | null>(null);
  $effect(() => {
    const aid = status.in_reply_to_account_id;
    replyToAcct = null;
    if (!status.in_reply_to_id || !aid) return;
    let alive = true;
    getAccountCached(aid)
      .then((a) => {
        if (alive) replyToAcct = a.acct;
      })
      .catch(() => {});
    return () => {
      alive = false;
    };
  });

  // 長い本文（主に hackers.pub の Article）はタイムラインを埋めないよう
  // 数行で畳み、「続きを読む」で全文を出す。記事だと知らせるフラグは無い
  // ので、描画後の実際の高さで判断する（背が高ければ畳む）。
  const COLLAPSE_PX = 360;
  let contentEl: HTMLDivElement | undefined = $state();
  let collapsible = $state(false);
  let expanded = $state(false);

  $effect(() => {
    // status.content を読むことで、別の投稿に差し替わったら測り直す。
    void status.content;
    // リーダーページでは畳まない。それ以外で背が高ければ畳む。
    collapsible = !full && !!contentEl && contentEl.scrollHeight > COLLAPSE_PX;
  });

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
    {#if status.in_reply_to_id}
      {#if replyToAcct}
        <a class="reply-to" href={`/@${replyToAcct}/${status.in_reply_to_id}`}>
          <Twemoji emoji="↩️" /> {$t('status.replyTo', { acct: replyToAcct })}
        </a>
      {:else}
        <span class="reply-to"><Twemoji emoji="↩️" /> {$t('status.replyToUnknown')}</span>
      {/if}
    {/if}

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
      <div
        class="content-wrap"
        class:collapsed={collapsible && !expanded}
        class:reader={full}
      >
        <div class="content" bind:this={contentEl}>
          {@html renderEmojis(status.content, status.emojis)}
        </div>
      </div>
      {#if !full}
        {#if status.title}
          <!-- 記事は専用のリーダーページで読む。短い記事でも入口を出す。 -->
          <a class="read-more" href={`/articles/${status.id}`}>{$t('status.readArticle')}</a>
        {:else if collapsible && !expanded}
          <button class="read-more" onclick={() => (expanded = true)}>{$t('status.readMore')}</button>
        {/if}
      {/if}
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
  /* 長文（Article）を畳むとき。下端をふわっと薄くして「まだ続く」を示す。 */
  .content-wrap.collapsed {
    max-height: 22rem;
    overflow: hidden;
    -webkit-mask-image: linear-gradient(to bottom, black 70%, transparent);
    mask-image: linear-gradient(to bottom, black 70%, transparent);
  }

  /* リーダー（記事ページ）の本文。畳まず、ゆったり読める行間と段落の間。 */
  .content-wrap.reader :global(.content) {
    line-height: 1.85;
  }
  .content-wrap.reader :global(.content p) {
    margin: 0.85rem 0;
  }
  .content-wrap.reader :global(.content h2:first-child) {
    font-size: 1.4rem;
    margin-top: 0;
  }

  .read-more {
    display: inline-block;
    margin-top: 0.25rem;
    padding: 0.2rem 0.7rem;
    font-size: var(--text-sm);
    color: var(--color-text-muted);
    background: var(--fill-soft);
    border: 1px solid var(--color-border);
    border-radius: 999px;
    text-decoration: none;
    cursor: pointer;
  }
  .read-more:hover {
    color: var(--color-text);
  }

  /* Article の本文には見出し（差し込んだ <h2> や本文中の h2/h3）が来る。
     ブラウザ既定の特大サイズだとタイムラインで浮くので、静かに整える。 */
  .content :global(h2),
  .content :global(h3),
  .content :global(h4) {
    font-size: var(--text-base, 1rem);
    font-weight: 600;
    margin: 0.6rem 0 0.3rem;
    line-height: 1.4;
  }
  .content :global(h2) {
    font-size: 1.1rem;
  }
  .content :global(pre) {
    overflow-x: auto;
  }

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

  /* 「@x への返信」。本文の上に、名前より小さく薄く。主張しすぎず、でも
     これが返信だと分かる程度に。リンクのときだけ hover で下線。 */
  .reply-to {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
    margin-bottom: 0.15rem;
    font-size: 0.8rem;
    color: var(--color-text-muted);
    text-decoration: none;
  }
  a.reply-to:hover {
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
    /* 子(名前・ハンドル)が中身の幅で踏ん張らず、行に収まるよう縮める
       のを許す。長い連合ハンドルがカードを突き破るのを止める。 */
    min-width: 0;
  }
  .quote-name {
    font-weight: 600;
    min-width: 0;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .quote-acct {
    color: var(--color-text-muted);
    min-width: 0;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .quote-content {
    font-size: var(--text-sm);
  }
</style>
