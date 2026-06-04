<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import {
    getNotifications,
    dismissNotification,
    clearNotifications,
    type Notification
  } from '$lib/api';
  import { isLoggedIn, clearToken } from '$lib/auth';
  import { renderEmojis } from '$lib/emoji';
  import { phrase } from '$lib/phrase';
  import StatusCard from '$lib/components/Status.svelte';

  let items = $state<Notification[]>([]);
  let nextMaxId = $state<string | null>(null);
  let loading = $state(false);
  let error = $state<string | null>(null);
  let initial = $state(true);

  onMount(() => {
    if (!isLoggedIn()) {
      goto('/');
      return;
    }
    void load(true);
  });

  async function load(reset: boolean) {
    if (loading) return;
    loading = true;
    error = null;

    if (reset) {
      items = [];
      nextMaxId = null;
    }

    try {
      const page = await getNotifications({ maxId: reset ? null : nextMaxId });
      items = reset ? page.items : [...items, ...page.items];
      nextMaxId = page.nextMaxId;
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'unknown';
      if (msg === 'unauthorized') {
        clearToken();
        goto('/');
        return;
      }
      error = 'うまく届きませんでした。もう一度、ためしますか?';
    } finally {
      loading = false;
      initial = false;
    }
  }

  // ひとつ消す。消えたらその場で一覧から外す。失敗したらそのまま。
  async function dismiss(n: Notification) {
    try {
      await dismissNotification(n.id);
      items = items.filter((x) => x.id !== n.id);
    } catch {
      // そっとしておく。
    }
  }

  async function clearAll() {
    if (items.length === 0) return;
    if (!confirm('通知を、すべて消しますか？')) return;
    try {
      await clearNotifications();
      items = [];
    } catch {
      // 失敗したら何もしない。
    }
  }

  // 「だれが・なにを」の一言。本文(status)は下にカードで出すので、ここは短く。
  function summary(n: Notification): string {
    switch (n.type) {
      case 'favourite':
        return 'がお気に入りにしました';
      case 'reblog':
        return 'がブーストしました';
      case 'follow':
        return 'にフォローされました';
      case 'follow_request':
        return 'からフォロー申請がきました';
      case 'mention':
        return 'から返信がきました';
      case 'status':
        return 'が投稿しました';
      case 'poll':
        return 'の投票が締め切られました';
      case 'update':
        return 'が投稿を編集しました';
      case 'reaction':
        return 'がリアクションしました';
      default:
        return 'からの通知';
    }
  }
</script>

<header
  class="timeline"
  style="display: flex; justify-content: space-between; align-items: baseline; gap: var(--space-3);"
>
  <h1 style="font-size: var(--text-lg);">通知</h1>
  <span style="display: flex; gap: var(--space-2);">
    <a class="chip" href="/timeline">タイムライン</a>
    {#if items.length > 0}
      <button class="chip" onclick={clearAll}>すべて消す</button>
    {/if}
  </span>
</header>

<section class="timeline">
  {#if error}
    <p class="error">{error}</p>
  {:else if initial && loading}
    <p class="loading">読んでいます…</p>
  {:else if items.length === 0 && !loading}
    <p class="prose-small">まだ、通知は、ありません。</p>
  {/if}

  {#each items as n (n.id)}
    <article class="notif">
      <header class="notif-head">
        <a class="notif-who" href={`/@${n.account.acct}`}>
          {#if n.account.avatar}
            <img class="avatar avatar-sm" src={n.account.avatar} alt="" loading="lazy" />
          {:else}
            <span class="avatar avatar-sm" aria-hidden="true"></span>
          {/if}
          <span class="display-name"
            >{@html renderEmojis(
              phrase(n.account.display_name || n.account.username),
              n.account.emojis
            )}</span
          >
        </a>
        <span class="notif-summary">{summary(n)}</span>
        <button class="chip notif-dismiss" onclick={() => dismiss(n)} aria-label="この通知を消す">
          ×
        </button>
      </header>

      {#if n.status}
        <StatusCard status={n.status} />
      {/if}
    </article>
  {/each}

  {#if !initial && loading}
    <p class="loading">読んでいます…</p>
  {/if}

  {#if nextMaxId && !loading}
    <button class="load-more" onclick={() => load(false)}>もっと読む</button>
  {/if}
</section>

<style>
  .notif {
    border-top: 1px solid var(--border, #e5e5e5);
    padding-top: var(--space-3);
  }
  .notif-head {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    margin-bottom: var(--space-2);
  }
  .notif-who {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    text-decoration: none;
    color: inherit;
  }
  .avatar-sm {
    width: 1.5rem;
    height: 1.5rem;
  }
  .notif-summary {
    color: var(--color-text-muted, #666);
    font-size: var(--text-sm);
  }
  .notif-dismiss {
    margin-left: auto;
  }
</style>
