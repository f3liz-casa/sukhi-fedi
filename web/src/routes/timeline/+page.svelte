<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { fetchTimeline, type Status, type TimelineKind } from '$lib/api';
  import { isLoggedIn, clearToken } from '$lib/auth';
  import StatusCard from '$lib/components/Status.svelte';
  import Composer from '$lib/components/Composer.svelte';

  let replyTo: Status | null = null;
  let composerOpen = false;

  function openCompose() {
    replyTo = null;
    composerOpen = true;
  }

  function onReply(ev: CustomEvent<Status>) {
    replyTo = ev.detail;
    composerOpen = true;
    // 上に composer があるのでスクロール。
    if (typeof window !== 'undefined') window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function onPosted(ev: CustomEvent<Status>) {
    // home / public のときは先頭に挿す。tag のときは混ぜずに閉じるだけ。
    if (kind === 'home' || kind === 'public') {
      items = [ev.detail, ...items];
    }
    composerOpen = false;
    replyTo = null;
  }

  function onCancel() {
    composerOpen = false;
    replyTo = null;
  }

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
    // タグタブはタグ文字列が無いと意味が無いので、まだ何も入って
    // いないときは取りに行かない(入力 → submit でロードされる)。
    if (next === 'tag' && !tag) {
      items = [];
      nextMaxId = null;
      error = null;
      initial = false;
      return;
    }
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

<header class="timeline" style="display: flex; justify-content: space-between; align-items: baseline; gap: var(--space-3);">
  <h1 style="font-size: var(--text-lg);">sukhi-fedi</h1>
  <span style="display: flex; gap: var(--space-2);">
    <a class="chip" href="/settings">設定</a>
    <button class="chip" on:click={openCompose}>書く</button>
    <button class="chip" on:click={signOut}>ログアウト</button>
  </span>
</header>

{#if composerOpen}
  <Composer
    {replyTo}
    prefillMention={!!replyTo}
    on:posted={onPosted}
    on:cancel={onCancel}
  />
{/if}

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
  {:else if initial && loading}
    <p class="loading">読んでいます…</p>
  {:else if items.length === 0 && !loading}
    <p class="prose-small">
      {#if kind === 'home'}
        まだ、ホームに、なにも届いていません。だれかをフォローすると、ここに集まります。
      {:else if kind === 'tag' && !tag}
        上の入力に、見たいタグを入れてください。
      {:else if kind === 'tag'}
        「#{tag}」を持つ投稿は、まだ見つかりません。
      {:else}
        まだ、なにも届いていません。
      {/if}
    </p>
  {/if}

  {#each items as s (s.id)}
    <StatusCard status={s} canReply on:reply={onReply} />
  {/each}

  {#if !initial && loading}
    <p class="loading">読んでいます…</p>
  {/if}

  {#if nextMaxId && !loading}
    <button class="load-more" on:click={() => load(false)}>もっと読む</button>
  {/if}
</section>
