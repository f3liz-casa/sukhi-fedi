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
  import { t } from '$lib/i18n';

  let { acct, kind }: { acct: string; kind: AccountKind } = $props();

  let owner = $state<Account | null>(null);
  let items = $state<Account[]>([]);
  let relations = $state(new Map<string, Relationship>());
  let meId = $state<string | null>(null);
  let nextMaxId = $state<string | null>(null);
  let loading = $state(false);
  let initial = $state(true);
  let error = $state<string | null>(null);

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
        ? $t('common.acctNotFound', { acct })
        : $t('common.deliverFailed');
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
    } catch {
      // 静かに止める
    } finally {
      loading = false;
    }
  }
</script>

{#if error}
  <p class="error">{error}</p>
  <p><a class="chip" href="/timeline">{$t('common.backToTimeline')}</a></p>
{:else if initial && loading}
  <p class="loading">{$t('common.loading')}</p>
{:else if owner}
  <header class="profile-head" style="padding-bottom: var(--space-3);">
    <p class="muted">
      <a href={`/@${owner.acct}`}>@{owner.acct}</a> {$t(
        kind === 'followers' ? 'accountList.possFollowers' : 'accountList.possFollowing'
      )}
    </p>
  </header>

  <section class="account-list">
    {#if items.length === 0}
      <p class="prose-small">{$t('accountList.empty')}</p>
    {/if}

    {#each items as a (a.id)}
      <AccountRow
        account={a}
        relationship={a.id === meId ? null : relations.get(a.id) ?? null}
      />
    {/each}

    {#if !initial && loading}
      <p class="loading">{$t('common.loading')}</p>
    {/if}

    {#if nextMaxId && !loading}
      <button class="load-more" onclick={more}>{$t('common.loadMore')}</button>
    {/if}
  </section>
{/if}
