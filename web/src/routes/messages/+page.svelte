<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import {
    getConversations,
    markConversationRead,
    type Conversation
  } from '$lib/api';
  import { isLoggedIn, clearToken } from '$lib/auth';
  import { renderEmojis } from '$lib/emoji';
  import { phrase } from '$lib/phrase';
  import StatusCard from '$lib/components/Status.svelte';

  let items = $state<Conversation[]>([]);
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
      const page = await getConversations({ maxId: reset ? null : nextMaxId });
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

  // スレッドをひらく。最新メッセージのスレッド表示へ移りつつ、その場で
  // 既読にする。既読にできなくても遷移は止めない(表示が主、印は従)。
  async function open(c: Conversation) {
    if (c.unread) {
      try {
        await markConversationRead(c.id);
        items = items.map((x) => (x.id === c.id ? { ...x, unread: false } : x));
      } catch {
        // 既読の同期失敗はそっとしておく。
      }
    }
    const s = c.last_status;
    if (s) goto(`/@${s.account.acct}/${s.id}`);
  }

  function withLabel(c: Conversation): string {
    const names = c.accounts.map((a) => a.display_name || a.username);
    if (names.length === 0) return '自分';
    return names.join('、');
  }
</script>

<header class="timeline" style="display: flex; justify-content: space-between; align-items: baseline; gap: var(--space-3);">
  <h1 style="font-size: var(--text-lg);">メッセージ</h1>
  <span style="display: flex; gap: var(--space-2);">
    <a class="chip" href="/timeline">タイムライン</a>
    <a class="chip" href="/search">さがす</a>
  </span>
</header>

<section class="timeline">
  {#if error}
    <p class="error">{error}</p>
  {:else if initial && loading}
    <p class="loading">読んでいます…</p>
  {:else if items.length === 0 && !loading}
    <p class="prose-small">
      まだ、だれとも、やりとりはありません。指名した相手にだけ届く投稿が、ここに集まります。
    </p>
  {/if}

  {#each items as c (c.id)}
    <article class="conversation" class:unread={c.unread}>
      <header class="conversation-with">
        <span class="conversation-people">
          {#each c.accounts as a (a.id)}
            <a class="conversation-person" href={`/@${a.acct}`}>
              {#if a.avatar}
                <img class="avatar avatar-sm" src={a.avatar} alt="" loading="lazy" />
              {:else}
                <span class="avatar avatar-sm" aria-hidden="true"></span>
              {/if}
            </a>
          {/each}
          <span class="display-name">{@html renderEmojis(phrase(withLabel(c)), c.accounts[0]?.emojis)}</span>
        </span>
        {#if c.unread}
          <span class="unread-dot" aria-label="未読"></span>
        {/if}
      </header>

      {#if c.last_status}
        <StatusCard status={c.last_status} />
      {/if}

      <button class="chip open-thread" onclick={() => open(c)}>スレッドをひらく</button>
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
  .conversation {
    border-top: 1px solid var(--border, #e5e5e5);
    padding-top: var(--space-3);
  }
  .conversation-with {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-2);
    margin-bottom: var(--space-2);
  }
  .conversation-people {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }
  .avatar-sm {
    width: 1.5rem;
    height: 1.5rem;
  }
  .unread-dot {
    width: 0.5rem;
    height: 0.5rem;
    border-radius: 50%;
    background: var(--accent, #4a7);
    flex: none;
  }
  .open-thread {
    margin-top: var(--space-2);
  }
</style>
