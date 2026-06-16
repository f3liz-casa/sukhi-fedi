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

  // 次のページを裏で先に取っておく置き場。クリックを待たずに用意して
  // おくので「もっと読む」が一瞬で返る。先読みが空なら本当に終わりと
  // 分かるので nextMaxId を畳んでボタンごと消す(Mastodon 系は最後の
  // ページでも max_id を返すため、これが無いと空のボタンが残る)。
  let prefetched = $state<{ items: Status[]; nextMaxId: string | null } | null>(null);

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

  // いまのタブ・フィルターでの 1 ページ取得。load と先読みで共有する。
  function fetchPage(maxId: string | null) {
    return fetchTimeline(kind, {
      tag: kind === 'tag' ? tag : undefined,
      maxId,
      onlyMedia,
      hideBoosts,
      hideSensitive
    });
  }

  async function load(reset: boolean) {
    if (loading) return;
    loading = true;
    error = null;

    if (reset) {
      items = [];
      nextMaxId = null;
      prefetched = null;
    }

    try {
      const page = await fetchPage(reset ? null : nextMaxId);
      items = reset ? page.items : [...items, ...page.items];
      // 0 件が返ったら、Link が次を匂わせていても終わり扱いにする。
      nextMaxId = page.items.length === 0 ? null : page.nextMaxId;
      if (nextMaxId) void prefetchNext(nextMaxId);
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

  // 次のページを裏で取って prefetched に置く。空なら終わりと分かるので
  // nextMaxId を畳む(= ボタンが消える)。cursor が古くなっていたら
  // (リセットや別タブで先へ進んだ)結果は捨てる。
  async function prefetchNext(cursor: string) {
    try {
      const page = await fetchPage(cursor);
      if (cursor !== nextMaxId) return;
      if (page.items.length === 0) {
        nextMaxId = null;
        prefetched = null;
      } else {
        prefetched = { items: page.items, nextMaxId: page.nextMaxId };
      }
    } catch {
      if (cursor === nextMaxId) prefetched = null;
    }
  }

  // 一瞬で湧くと目が追えず落ち着かないので、短い静かな「間」を置いてから
  // 差し込む ── 認知負荷を上げない程度のディレイ。
  const REVEAL_DELAY_MS = 280;
  let revealing = $state(false);
  const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

  // 「もっと読む」。先読みが手元にあれば、行き先を先へ進めて、その次の
  // ページの取得を押した瞬間に非同期で走らせる(reveal は待たせない)。
  // そのうえで静かな間を置いてから手元のぶんを差す。先読みが間に合って
  // いなければ(押すのが早すぎた等)その場で取りに行く従来どおりの保険。
  async function showMore() {
    if (loading || revealing) return;
    if (!prefetched) {
      void load(false);
      return;
    }
    const batch = prefetched;
    prefetched = null;
    nextMaxId = batch.nextMaxId;
    if (nextMaxId) void prefetchNext(nextMaxId);
    revealing = true;
    await sleep(REVEAL_DELAY_MS);
    items = [...items, ...batch.items];
    revealing = false;
  }

  function selectKind(next: TimelineKind) {
    if (next === kind) return;
    kind = next;
    // タグタブはタグ文字列が無いと意味が無いので、まだ何も入って
    // いないときは取りに行かない(入力 → submit でロードされる)。
    if (next === 'tag' && !tag) {
      items = [];
      nextMaxId = null;
      prefetched = null;
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
  <TimelineFilter
    bind:onlyMedia
    bind:hideBoosts
    bind:hideSensitive
    showHideBoosts={kind === 'home'}
    onchange={applyFilters}
  />
</nav>

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

  {#if !initial && (loading || revealing)}
    <p class="loading">{$t('common.loading')}</p>
  {/if}

  {#if nextMaxId && !loading && !revealing}
    <button class="load-more" onclick={showMore}>{$t('common.loadMore')}</button>
  {/if}
</section>
