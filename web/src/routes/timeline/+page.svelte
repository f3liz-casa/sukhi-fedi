<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { fetchTimeline, type Status, type TimelineKind } from '$lib/api';
  import { isLoggedIn, clearToken } from '$lib/auth';
  import StatusCard from '$lib/components/Status.svelte';

  let kind: TimelineKind = 'home';
  let tag = '';
  let pendingTag = '';

  let items: Status[] = [];
  let nextMaxId: string | null = null;
  let loading = false;
  let error: string | null = null;
  let initial = true;

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
      const page = await fetchTimeline(kind, {
        tag: kind === 'tag' ? tag : undefined,
        maxId: reset ? null : nextMaxId
      });
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

  function selectKind(next: TimelineKind) {
    if (next === kind) return;
    kind = next;
    void load(true);
  }

  function submitTag() {
    const t = pendingTag.trim().replace(/^#/, '');
    if (!t) return;
    tag = t;
    kind = 'tag';
    void load(true);
  }

  function signOut() {
    clearToken();
    goto('/');
  }
</script>

<header class="timeline" style="display: flex; justify-content: space-between; align-items: baseline;">
  <h1 style="font-size: var(--text-lg);">sukhi-fedi</h1>
  <button class="chip" on:click={signOut}>ログアウト</button>
</header>

<nav class="tabs timeline" aria-label="タイムラインの選び方">
  <button
    type="button"
    aria-pressed={kind === 'home'}
    on:click={() => selectKind('home')}
  >ホーム</button>
  <button
    type="button"
    aria-pressed={kind === 'public'}
    on:click={() => selectKind('public')}
  >みんな</button>
  <button
    type="button"
    aria-pressed={kind === 'tag'}
    on:click={() => selectKind('tag')}
  >タグ</button>
</nav>

{#if kind === 'tag'}
  <form
    class="timeline form"
    on:submit|preventDefault={submitTag}
    style="margin-bottom: var(--space-4);"
  >
    <label class="stack-tight">
      <span>タグ（#は要りません）</span>
      <input type="text" bind:value={pendingTag} placeholder="例: しずか" />
    </label>
  </form>
{/if}

<section class="timeline">
  {#if error}
    <p class="error">{error}</p>
  {/if}

  {#if initial && loading}
    <p class="loading">読んでいます…</p>
  {:else if items.length === 0 && !loading}
    <p class="prose-small">
      {#if kind === 'home'}
        まだ、ホームに、なにも届いていません。だれかをフォローすると、ここに集まります。
      {:else if kind === 'tag'}
        そのタグを持つ投稿は、まだ見つかりません。
      {:else}
        まだ、なにも届いていません。
      {/if}
    </p>
  {/if}

  {#each items as s (s.id)}
    <StatusCard status={s} />
  {/each}

  {#if !initial && loading}
    <p class="loading">読んでいます…</p>
  {/if}

  {#if nextMaxId && !loading}
    <button class="load-more" on:click={() => load(false)}>もっと読む</button>
  {/if}
</section>
