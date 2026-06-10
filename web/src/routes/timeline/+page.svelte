<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { fetchTimeline, type Status, type TimelineKind } from '$lib/api';
  import { isLoggedIn, clearToken } from '$lib/auth';
  import { composeRequest } from '$lib/compose';
  import StatusCard from '$lib/components/Status.svelte';
  import Composer from '$lib/components/Composer.svelte';
  import TimelineFilter from '$lib/components/TimelineFilter.svelte';
  import { t } from '$lib/i18n';

  let replyTo = $state<Status | null>(null);
  let composerOpen = $state(false);

  function openCompose() {
    replyTo = null;
    composerOpen = true;
  }

  // ヘッダーの「書く」から。開いたら 0 に戻す(戻さないと、あとで
  // このページに来直したときにまた開いてしまう)。
  $effect(() => {
    if ($composeRequest > 0) {
      composeRequest.set(0);
      openCompose();
    }
  });

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

  // フィルターを変えたら先頭から読み直す。
  function applyFilters() {
    void load(true);
  }
</script>

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

<div class="timeline">
  <TimelineFilter
    bind:onlyMedia
    bind:hideBoosts
    bind:hideSensitive
    showHideBoosts={kind === 'home'}
    onchange={applyFilters}
  />
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
