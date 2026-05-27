<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import {
    lookupAccount,
    getAccountStatuses,
    getRelationships,
    verifyCredentials,
    type Account,
    type Relationship,
    type Status
  } from '$lib/api';
  import { isLoggedIn, clearToken } from '$lib/auth';
  import StatusCard from '$lib/components/Status.svelte';
  import FollowButton from '$lib/components/FollowButton.svelte';
  import { phrase } from '$lib/phrase';

  let account = $state<Account | null>(null);
  let me = $state<Account | null>(null);
  let rel = $state<Relationship | null>(null);
  let items = $state<Status[]>([]);
  let nextMaxId = $state<string | null>(null);
  let loading = $state(false);
  let error = $state<string | null>(null);
  let initial = $state(true);

  let acct = $derived($page.params.acct ?? '');
  let isSelf = $derived(!!account && !!me && me.id === account.id);

  onMount(() => {
    void load();
  });

  async function load() {
    loading = true;
    error = null;
    try {
      account = await lookupAccount(acct);
      // 自分かどうかを判定するため、ログイン時だけ自分を引く。
      if (isLoggedIn()) {
        try {
          me = await verifyCredentials();
        } catch {
          me = null;
        }
        if (me && me.id !== account.id) {
          const rs = await getRelationships([account.id]);
          rel = rs[0] ?? null;
        }
      }
      const page1 = await getAccountStatuses(account.id);
      items = page1.items;
      nextMaxId = page1.nextMaxId;
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      if (msg === 'unauthorized') {
        clearToken();
        void goto('/');
        return;
      }
      if (msg === 'not_found') {
        error = `「@${acct}」さんは、見つかりませんでした。`;
      } else {
        error = 'うまく届きませんでした。';
      }
    } finally {
      loading = false;
      initial = false;
    }
  }

  async function loadMore() {
    if (!account || loading) return;
    loading = true;
    try {
      const p = await getAccountStatuses(account.id, { maxId: nextMaxId });
      items = [...items, ...p.items];
      nextMaxId = p.nextMaxId;
    } catch {
      // 続きが取れなかったら静かに止める。
    } finally {
      loading = false;
    }
  }
</script>

{#if error}
  <p class="error">{error}</p>
  <p><a class="chip" href="/timeline">タイムラインへ戻る</a></p>
{:else if initial && loading}
  <p class="loading">読んでいます…</p>
{:else if account}
  <header class="profile-head">
    {#if account.header}
      <img class="profile-header" src={account.header} alt="" loading="lazy" />
    {/if}
    <div class="profile-id">
      {#if account.avatar}
        <img class="avatar avatar-lg" src={account.avatar} alt="" />
      {:else}
        <span class="avatar avatar-lg" aria-hidden="true"></span>
      {/if}
      <div class="stack-tight" style="flex: 1;">
        <p class="display-name" style="font-size: var(--text-lg);">
          {@html phrase(account.display_name || account.username)}
        </p>
        <p class="muted">@{account.acct}</p>
      </div>
      {#if isSelf}
        <a class="chip" href="/settings">編集</a>
      {:else}
        <FollowButton accountId={account.id} relationship={rel} onchange={(r) => (rel = r)} />
      {/if}
    </div>

    {#if account.note}
      <div class="profile-note">{@html account.note}</div>
    {/if}

    <p class="profile-counts">
      <a href={`/@${account.acct}/following`}>
        <strong>{account.following_count ?? 0}</strong> フォロー中
      </a>
      <a href={`/@${account.acct}/followers`}>
        <strong>{account.followers_count ?? 0}</strong> フォロワー
      </a>
      <span><strong>{account.statuses_count ?? 0}</strong> 投稿</span>
    </p>
  </header>

  <section class="timeline">
    {#if items.length === 0 && !loading}
      <p class="prose-small">まだ、投稿は、ありません。</p>
    {/if}

    {#each items as s (s.id)}
      <StatusCard status={s} />
    {/each}

    {#if !initial && loading}
      <p class="loading">読んでいます…</p>
    {/if}

    {#if nextMaxId && !loading}
      <button class="load-more" onclick={loadMore}>もっと読む</button>
    {/if}
  </section>
{/if}
