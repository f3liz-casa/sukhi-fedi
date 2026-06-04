<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { getBookmarks, type Status } from '$lib/api';
  import { isLoggedIn, clearToken } from '$lib/auth';
  import StatusCard from '$lib/components/Status.svelte';

  let items = $state<Status[]>([]);
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
      const page = await getBookmarks({ maxId: reset ? null : nextMaxId });
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

  // ブックマークを外したら、その場でこの一覧から外す。
  function onUpdate(s: Status) {
    if (!s.bookmarked) items = items.filter((it) => it.id !== s.id);
  }
</script>

<header
  class="timeline"
  style="display: flex; justify-content: space-between; align-items: baseline; gap: var(--space-3);"
>
  <h1 style="font-size: var(--text-lg);">ブックマーク</h1>
  <span style="display: flex; gap: var(--space-2);">
    <a class="chip" href="/timeline">タイムライン</a>
  </span>
</header>

<section class="timeline">
  {#if error}
    <p class="error">{error}</p>
  {:else if initial && loading}
    <p class="loading">読んでいます…</p>
  {:else if items.length === 0 && !loading}
    <p class="prose-small">まだ、しおりは、はさんでいません。</p>
  {/if}

  {#each items as s (s.id)}
    <StatusCard
      status={s}
      onupdate={onUpdate}
      ondelete={(d) => (items = items.filter((it) => it.id !== d.id))}
    />
  {/each}

  {#if !initial && loading}
    <p class="loading">読んでいます…</p>
  {/if}

  {#if nextMaxId && !loading}
    <button class="load-more" onclick={() => load(false)}>もっと読む</button>
  {/if}
</section>
