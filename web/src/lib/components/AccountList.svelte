<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import {
    lookupAccount,
    type Account,
    type Relationship
  } from '$lib/api';
  import { clearToken } from '$lib/auth';
  import { loadAccountList, type AccountKind } from '$lib/relations';
  import AccountRow from './AccountRow.svelte';

  export let acct: string;
  export let kind: AccountKind;

  let owner: Account | null = null;
  let items: Account[] = [];
  let relations = new Map<string, Relationship>();
  let meId: string | null = null;
  let nextMaxId: string | null = null;
  let loading = false;
  let initial = true;
  let error: string | null = null;

  $: heading = kind === 'followers' ? 'フォロワー' : 'フォロー中';

  onMount(() => {
    void start();
  });

  async function start() {
    loading = true;
    error = null;
    try {
      owner = await lookupAccount(acct);
      const r = await loadAccountList(kind, owner.id);
      items = r.page.items;
      nextMaxId = r.page.nextMaxId;
      relations = r.relations;
      meId = r.meId;
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      if (msg === 'unauthorized') {
        clearToken();
        void goto('/');
        return;
      }
      error = msg === 'not_found'
        ? `「@${acct}」さんは、見つかりませんでした。`
        : 'うまく届きませんでした。';
    } finally {
      loading = false;
      initial = false;
    }
  }

  async function more() {
    if (!owner || loading) return;
    loading = true;
    try {
      const r = await loadAccountList(kind, owner.id, { maxId: nextMaxId });
      items = [...items, ...r.page.items];
      nextMaxId = r.page.nextMaxId;
      for (const [k, v] of r.relations) relations.set(k, v);
      relations = relations;
    } catch {
      // 静かに止める
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
{:else if owner}
  <header class="profile-head" style="padding-bottom: var(--space-3);">
    <p class="muted">
      <a href={`/@${owner.acct}`}>@{owner.acct}</a> の {heading}
    </p>
  </header>

  <section class="account-list">
    {#if items.length === 0}
      <p class="prose-small">まだ、いません。</p>
    {/if}

    {#each items as a (a.id)}
      <AccountRow
        account={a}
        relationship={a.id === meId ? null : relations.get(a.id) ?? null}
      />
    {/each}

    {#if !initial && loading}
      <p class="loading">読んでいます…</p>
    {/if}

    {#if nextMaxId && !loading}
      <button class="load-more" on:click={more}>もっと読む</button>
    {/if}
  </section>
{/if}
