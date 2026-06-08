<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { fetchTimeline, type Status, type TimelineKind } from '$lib/api';
  import { isLoggedIn, clearToken } from '$lib/auth';
  import StatusCard from '$lib/components/Status.svelte';
  import Composer from '$lib/components/Composer.svelte';
  import { t } from '$lib/i18n';

  let replyTo = $state<Status | null>(null);
  let composerOpen = $state(false);

  function openCompose() {
    replyTo = null;
    composerOpen = true;
  }

  function onReply(s: Status) {
    replyTo = s;
    composerOpen = true;
    // 上に composer があるのでスクロール。
    if (typeof window !== 'undefined') window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function onPosted(s: Status) {
    // home / public のときは先頭に挿す。tag のときは混ぜずに閉じるだけ。
    if (kind === 'home' || kind === 'public') {
      items = [s, ...items];
    }
    composerOpen = false;
    replyTo = null;
  }

  function onCancel() {
    composerOpen = false;
    replyTo = null;
  }

  function onDelete(s: Status) {
    items = items.filter((it) => it.id !== s.id);
  }

  let kind = $state<TimelineKind>('home');
  let tag = $state('');
  let pendingTag = $state('');

  let items = $state<Status[]>([]);
  let nextMaxId = $state<string | null>(null);
  let loading = $state(false);
  let error = $state<string | null>(null);
  let initial = $state(true);

  // 表示フィルター（home/public/tag タブとは別軸）。変えたら頭から読み直す。
  // RT を隠すのは home だけ実効（public/tag はブーストを混ぜない）。
  let onlyMedia = $state(false);
  let hideBoosts = $state(false);
  let hideSensitive = $state(false);
  let filterOpen = $state(false);
  let activeFilters = $derived(
    [onlyMedia, kind === 'home' && hideBoosts, hideSensitive].filter(Boolean).length
  );

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
        maxId: reset ? null : nextMaxId,
        onlyMedia,
        hideBoosts,
        hideSensitive
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
      error = $t('common.deliverFailedRetry');
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

  // フィルターを変えたら先頭から読み直す。
  function applyFilters() {
    void load(true);
  }
</script>

<header class="timeline page-head">
  <h1>sukhi-fedi</h1>
  <span class="page-nav">
    <a class="chip" href="/notifications">{$t('nav.notifications')}</a>
    <a class="chip" href="/messages">{$t('nav.messages')}</a>
    <a class="chip" href="/bookmarks">{$t('nav.bookmarks')}</a>
    <a class="chip" href="/favourites">{$t('nav.favourites')}</a>
    <a class="chip" href="/lists">{$t('nav.lists')}</a>
    <a class="chip" href="/search">{$t('nav.search')}</a>
    <a class="chip" href="/settings">{$t('nav.settings')}</a>
    <button class="chip" onclick={openCompose}>{$t('nav.compose')}</button>
    <button class="chip" onclick={signOut}>{$t('nav.logout')}</button>
  </span>
</header>

{#if composerOpen}
  <Composer
    {replyTo}
    prefillMention={!!replyTo}
    onposted={onPosted}
    oncancel={onCancel}
  />
{/if}

<nav class="tabs timeline" aria-label={$t('timeline.tabsLabel')}>
  <button
    type="button"
    aria-pressed={kind === 'home'}
    onclick={() => selectKind('home')}
  >{$t('timeline.tabHome')}</button>
  <button
    type="button"
    aria-pressed={kind === 'public'}
    onclick={() => selectKind('public')}
  >{$t('timeline.tabPublic')}</button>
  <button
    type="button"
    aria-pressed={kind === 'tag'}
    onclick={() => selectKind('tag')}
  >{$t('timeline.tabTag')}</button>
</nav>

<div class="filter-bar timeline">
  <button
    type="button"
    class="chip"
    aria-expanded={filterOpen}
    aria-haspopup="menu"
    onclick={() => (filterOpen = !filterOpen)}
  >
    {$t('timeline.filter')}{activeFilters > 0 ? ` (${activeFilters})` : ''}
  </button>
  {#if filterOpen}
    <div class="filter-menu" role="menu">
      <label class="filter-row">
        <input type="checkbox" bind:checked={onlyMedia} onchange={applyFilters} />
        <span>{$t('timeline.onlyMedia')}</span>
      </label>
      {#if kind === 'home'}
        <label class="filter-row">
          <input type="checkbox" bind:checked={hideBoosts} onchange={applyFilters} />
          <span>{$t('timeline.hideBoosts')}</span>
        </label>
      {/if}
      <label class="filter-row">
        <input type="checkbox" bind:checked={hideSensitive} onchange={applyFilters} />
        <span>{$t('timeline.hideSensitive')}</span>
      </label>
    </div>
  {/if}
</div>

{#if kind === 'tag'}
  <form
    class="timeline form"
    onsubmit={(e) => {
      e.preventDefault();
      submitTag();
    }}
    style="margin-bottom: var(--space-4);"
  >
    <label class="stack-tight">
      <span>{$t('timeline.tagLabel')}</span>
      <input type="text" bind:value={pendingTag} placeholder={$t('timeline.tagPlaceholder')} />
    </label>
  </form>
{/if}

<section class="timeline">
  {#if error}
    <p class="error">{error}</p>
  {:else if initial && loading}
    <p class="loading">{$t('common.loading')}</p>
  {:else if items.length === 0 && !loading}
    <p class="prose-small">
      {#if kind === 'home'}
        {$t('timeline.emptyHome')}
      {:else if kind === 'tag' && !tag}
        {$t('timeline.emptyTagPrompt')}
      {:else if kind === 'tag'}
        {$t('timeline.emptyTag', { tag })}
      {:else}
        {$t('timeline.emptyGeneric')}
      {/if}
    </p>
  {/if}

  {#each items as s (s.id)}
    <StatusCard status={s} canReply onreply={onReply} ondelete={onDelete} />
  {/each}

  {#if !initial && loading}
    <p class="loading">{$t('common.loading')}</p>
  {/if}

  {#if nextMaxId && !loading}
    <button class="load-more" onclick={() => load(false)}>{$t('common.loadMore')}</button>
  {/if}
</section>

<style>
  .filter-bar {
    position: relative;
    margin-bottom: var(--space-3);
  }
  .filter-menu {
    position: absolute;
    z-index: 10;
    margin-top: 0.25rem;
    min-width: 14rem;
    max-width: calc(100vw - 2rem);
    padding: 0.25rem;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    background: var(--color-surface);
  }
  .filter-row {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.375rem 0.5rem;
    cursor: pointer;
  }
  .filter-row:hover {
    background: var(--fill-hover);
  }
</style>
