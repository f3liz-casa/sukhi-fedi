<script lang="ts">
  import type { Status, Reaction } from '$lib/api';
  import * as api from '$lib/api';
  import ReactionPicker from './ReactionPicker.svelte';

  let {
    status,
    // 返信ボタンを出すか。タイムラインでは true、プロフィール一覧では false
    // など、置き場ごとに切り替えたい。
    canReply = false,
    onreply,
    onupdate
  }: {
    status: Status;
    canReply?: boolean;
    onreply?: (s: Status) => void;
    onupdate?: (s: Status) => void;
  } = $props();

  // Display name falls back to username when servers omit it (Misskey
  // sometimes does for fresh actors).
  let name = $derived(status.account.display_name || status.account.username);
  let avatar = $derived(status.account.avatar || null);
  let ts = $derived(formatTime(status.created_at));

  // ローカル state は楽観更新用。prop が差し替わったら sync する。
  let reactions = $state<Reaction[]>([]);
  let favourited = $state(false);
  let favCount = $state(0);
  let pickerOpen = $state(false);

  $effect(() => {
    reactions = status.reactions ?? [];
    favourited = !!status.favourited;
    favCount = status.favourites_count ?? 0;
  });

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

  async function toggleReaction(emoji: string) {
    const snapshot = reactions;
    const idx = reactions.findIndex((r) => r.name === emoji);

    if (idx >= 0 && reactions[idx].me) {
      const next = { ...reactions[idx], me: false, count: reactions[idx].count - 1 };
      reactions =
        next.count <= 0
          ? reactions.filter((_, i) => i !== idx)
          : reactions.map((x, i) => (i === idx ? next : x));
      try {
        const s = await api.unreact(status.id, emoji);
        onupdate?.(s);
      } catch {
        reactions = snapshot;
      }
    } else if (idx >= 0) {
      const next = { ...reactions[idx], me: true, count: reactions[idx].count + 1 };
      reactions = reactions.map((x, i) => (i === idx ? next : x));
      try {
        const s = await api.react(status.id, emoji);
        onupdate?.(s);
      } catch {
        reactions = snapshot;
      }
    } else {
      reactions = [...reactions, { name: emoji, count: 1, me: true }];
      try {
        const s = await api.react(status.id, emoji);
        onupdate?.(s);
      } catch {
        reactions = snapshot;
      }
    }
  }

  function pickFromPicker(emoji: string) {
    pickerOpen = false;
    toggleReaction(emoji);
  }

  async function toggleFavourite() {
    const wasFav = favourited;
    const before = favCount;
    favourited = !wasFav;
    favCount = wasFav ? Math.max(0, before - 1) : before + 1;
    try {
      const s = wasFav ? await api.unfavourite(status.id) : await api.favourite(status.id);
      onupdate?.(s);
    } catch {
      favourited = wasFav;
      favCount = before;
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

    {#if reactions.length > 0}
      <div class="reactions" aria-label="リアクション">
        {#each reactions as r (r.name)}
          <button
            type="button"
            class="reaction-chip"
            class:me={r.me}
            title={r.name}
            onclick={() => toggleReaction(r.name)}
          >
            {#if r.url}
              <img class="emoji" src={r.url} alt={r.name} loading="lazy" />
            {:else}
              <span class="emoji">{r.name}</span>
            {/if}
            <span class="count">{r.count}</span>
          </button>
        {/each}
      </div>
    {/if}

    <footer class="status-actions">
      <button type="button" class="chip" onclick={() => (pickerOpen = !pickerOpen)} aria-haspopup="dialog">
        ＋
      </button>
      <button
        type="button"
        class="chip"
        class:active={favourited}
        onclick={toggleFavourite}
        aria-pressed={favourited}
      >
        ⭐ {favCount > 0 ? favCount : ''}
      </button>
      {#if canReply}
        <button type="button" class="chip" onclick={() => onreply?.(status)}>
          返信
        </button>
      {/if}
    </footer>

    {#if pickerOpen}
      <div class="picker-anchor">
        <ReactionPicker onpick={pickFromPicker} onclose={() => (pickerOpen = false)} />
      </div>
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
    border: 1px solid transparent;
    font-size: 0.875rem;
    line-height: 1.4;
    cursor: pointer;
  }
  .reaction-chip:hover {
    background: var(--reaction-bg-hover, rgba(127, 127, 127, 0.2));
  }
  .reaction-chip.me {
    background: var(--reaction-bg-me, rgba(99, 102, 241, 0.18));
    border-color: var(--reaction-border-me, rgba(99, 102, 241, 0.5));
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
  .status-actions .chip.active {
    background: var(--reaction-bg-me, rgba(99, 102, 241, 0.18));
  }
  .picker-anchor {
    position: relative;
    margin-top: 0.25rem;
  }
</style>
