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
  import { t } from '$lib/i18n';

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
      error = $t('common.deliverFailedRetry');
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
    if (!confirm($t('notif.confirmClear'))) return;
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

<p class="back-row timeline"><a class="back-link" href="/timeline">← {$t('common.timeline')}</a></p>
<header class="timeline page-head">
  <h1>{$t('notif.title')}</h1>
  {#if items.length > 0}
    <span class="page-nav">
      <button class="chip" onclick={clearAll}>{$t('notif.clearAll')}</button>
    </span>
  {/if}
</header>

<section class="timeline">
  {#if error}
    <p class="error">{error}</p>
  {:else if initial && loading}
    <p class="loading">{$t('common.loading')}</p>
  {:else if items.length === 0 && !loading}
    <p class="prose-small">{$t('notif.empty')}</p>
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
