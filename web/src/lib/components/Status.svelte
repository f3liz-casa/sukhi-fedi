<script lang="ts">
  import type { Status } from '$lib/api';

  let {
    status,
    // 返信ボタンを出すか。タイムラインでは true、プロフィール一覧では false
    // など、置き場ごとに切り替えたい。
    canReply = false,
    onreply
  }: {
    status: Status;
    canReply?: boolean;
    onreply?: (s: Status) => void;
  } = $props();

  // Display name falls back to username when servers omit it (Misskey
  // sometimes does for fresh actors).
  let name = $derived(status.account.display_name || status.account.username);
  let avatar = $derived(status.account.avatar || null);
  let ts = $derived(formatTime(status.created_at));

  function formatTime(iso: string): string {
    try {
      const d = new Date(iso);
      const now = Date.now();
      const diff = (now - d.getTime()) / 1000;
      if (diff < 60) return 'いま';
      if (diff < 3600) return Math.floor(diff / 60) + ' 分前';
      if (diff < 86_400) return Math.floor(diff / 3600) + ' 時間前';
      if (diff < 86_400 * 7) return Math.floor(diff / 86_400) + ' 日前';
      return d.toLocaleDateString('ja-JP');
    } catch {
      return iso;
    }
  }
</script>

<article class="status">
  {#if avatar}
    <img class="avatar" src={avatar} alt="" loading="lazy" />
  {:else}
    <span class="avatar" aria-hidden="true"></span>
  {/if}

  <div class="body">
    <header class="meta">
      <a class="display-name" href={`/@${status.account.acct}`}>{name}</a>
      <a href={`/@${status.account.acct}`}>@{status.account.acct}</a>
      <span>·</span>
      <a href={status.url ?? '#'} rel="external noopener">{ts}</a>
    </header>

    {#if status.spoiler_text}
      <details>
        <summary>{status.spoiler_text}</summary>
        <div class="content">{@html status.content}</div>
      </details>
    {:else}
      <div class="content">{@html status.content}</div>
    {/if}

    {#if status.media_attachments.length > 0}
      <div class="media">
        {#each status.media_attachments as m (m.id)}
          {#if m.type === 'image'}
            <img src={m.preview_url || m.url} alt={m.description || ''} loading="lazy" />
          {/if}
        {/each}
      </div>
    {/if}

    {#if status.reactions && status.reactions.length > 0}
      <div class="reactions" aria-label="リアクション">
        {#each status.reactions as r (r.name)}
          <span class="reaction-chip" class:me={r.me} title={r.name}>
            {#if r.url}
              <img class="emoji" src={r.url} alt={r.name} loading="lazy" />
            {:else}
              <span class="emoji">{r.name}</span>
            {/if}
            <span class="count">{r.count}</span>
          </span>
        {/each}
      </div>
    {/if}

    {#if canReply}
      <footer class="status-actions">
        <button type="button" class="chip" onclick={() => onreply?.(status)}>
          返信
        </button>
      </footer>
    {/if}
  </div>
</article>

<style>
  .reactions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.25rem;
    margin-top: 0.5rem;
  }
  .reaction-chip {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
    padding: 0.125rem 0.5rem;
    border-radius: 999px;
    background: var(--reaction-bg, rgba(127, 127, 127, 0.12));
    font-size: 0.875rem;
    line-height: 1.4;
  }
  .reaction-chip.me {
    background: var(--reaction-bg-me, rgba(99, 102, 241, 0.18));
  }
  .reaction-chip .emoji {
    font-size: 1rem;
  }
  .reaction-chip img.emoji {
    width: 1.125rem;
    height: 1.125rem;
    vertical-align: -0.2em;
  }
  .reaction-chip .count {
    font-variant-numeric: tabular-nums;
    color: var(--muted, #666);
  }
</style>
