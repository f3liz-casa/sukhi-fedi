<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import {
    getNotifications,
    dismissNotification,
    clearNotifications,
    type Notification
  } from '$lib/api';
  import { DIRECT_TYPES, markSeen, clearCounts, type Tier } from '$lib/notify';
  import { isLoggedIn, clearToken } from '$lib/auth';
  import { renderEmojis } from '$lib/emoji';
  import { phrase } from '$lib/phrase';
  import StatusCard from '$lib/components/Status.svelte';
  import { t } from '$lib/i18n';

  // ふたつのタブ(lib/notify.ts の層と同じ割り方):
  //   あなたへ — 返信・DM・フォロー申請。会話だから、先に出る。
  //   反応     — お気に入りやブーストの郵便受け。開きに来たとき
  //              だけ中身が見える。
  let tier = $state<Tier>('direct');

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
    // 読んでいる途中でタブが切り替わっても、この一回はこのタブの分。
    const target = tier;
    loading = true;
    error = null;

    if (reset) {
      items = [];
      nextMaxId = null;
    }

    try {
      const page = await getNotifications({
        maxId: reset ? null : nextMaxId,
        types: target === 'direct' ? DIRECT_TYPES : undefined,
        excludeTypes: target === 'ambient' ? DIRECT_TYPES : undefined
      });
      items = reset ? page.items : [...items, ...page.items];
      nextMaxId = page.nextMaxId;
      // 見せたところまでが「見た」。開いたタブの分だけ既読が進む —
      // もう片方のタブの景色は、まだ動かさない。
      if (reset) markSeen(target, page.items[0]?.id);
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

  function selectTier(next: Tier) {
    if (next === tier) return;
    tier = next;
    void load(true);
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
    if (!confirm($t('notif.confirmClear'))) return;
    try {
      await clearNotifications();
      items = [];
      // サーバ側は両方のタブとも空になったので、ヘッダーの数も空に。
      clearCounts();
    } catch {
      // 失敗したら何もしない。
    }
  }

  // 「だれが・なにを」の一言。本文(status)は下にカードで出すので、ここは短く。
  function summary(n: Notification): string {
    switch (n.type) {
      case 'favourite':
        return $t('notif.favourited');
      case 'reblog':
        return $t('notif.reblogged');
      case 'follow':
        return $t('notif.followed');
      case 'follow_request':
        return $t('notif.followRequest');
      case 'mention':
        return $t('notif.mentioned');
      case 'status':
        return $t('notif.posted');
      case 'poll':
        return $t('notif.pollEnded');
      case 'update':
        return $t('notif.updated');
      case 'reaction':
        return $t('notif.reacted');
      default:
        return $t('notif.generic');
    }
  }
</script>

<header class="timeline page-head">
  <h1>{$t('notif.title')}</h1>
  {#if items.length > 0}
    <span class="page-nav">
      <button class="chip" onclick={clearAll}>{$t('notif.clearAll')}</button>
    </span>
  {/if}
</header>

<nav class="tabs timeline" aria-label={$t('notif.tabsLabel')}>
  <button
    type="button"
    aria-pressed={tier === 'direct'}
    onclick={() => selectTier('direct')}
  >{$t('notif.tabToYou')}</button>
  <button
    type="button"
    aria-pressed={tier === 'ambient'}
    onclick={() => selectTier('ambient')}
  >{$t('notif.tabReactions')}</button>
</nav>

<section class="timeline">
  {#if error}
    <p class="error">{error}</p>
  {:else if initial && loading}
    <p class="loading">{$t('common.loading')}</p>
  {:else if items.length === 0 && !loading}
    <p class="prose-small">
      {tier === 'direct' ? $t('notif.emptyToYou') : $t('notif.emptyReactions')}
    </p>
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
        <button class="chip notif-dismiss" onclick={() => dismiss(n)} aria-label={$t('notif.dismiss')}>
          ×
        </button>
      </header>

      {#if n.status}
        <StatusCard status={n.status} />
      {/if}
    </article>
  {/each}

  {#if !initial && loading}
    <p class="loading">{$t('common.loading')}</p>
  {/if}

  {#if nextMaxId && !loading}
    <button class="load-more" onclick={() => load(false)}>{$t('common.loadMore')}</button>
  {/if}
</section>

<style>
  .notif {
    border-top: 1px solid var(--color-border);
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
  .notif-summary {
    color: var(--color-text-muted);
    font-size: var(--text-sm);
  }
  .notif-dismiss {
    margin-left: auto;
  }
</style>
