<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import {
    getList,
    fetchListTimeline,
    getListAccounts,
    addToList,
    removeFromList,
    lookupAccount,
    type List,
    type Status,
    type Account
  } from '$lib/api';
  import { isLoggedIn, clearToken } from '$lib/auth';
  import StatusCard from '$lib/components/Status.svelte';
  import AccountActionRow from '$lib/components/AccountActionRow.svelte';

  let id = $derived($page.params.id ?? '');

  let list = $state<List | null>(null);
  let items = $state<Status[]>([]);
  let nextMaxId = $state<string | null>(null);
  let loading = $state(false);
  let initial = $state(true);
  let error = $state<string | null>(null);

  // メンバー（<details> を開いたとき一度だけ読む）。
  let members = $state<Account[]>([]);
  let membersLoaded = $state(false);
  let addAcct = $state('');
  let addPending = $state(false);
  let addError = $state<string | null>(null);

  onMount(() => {
    if (!isLoggedIn()) {
      goto('/');
      return;
    }
    void load();
  });

  async function load() {
    loading = true;
    error = null;
    try {
      list = await getList(id);
      const p = await fetchListTimeline(id);
      items = p.items;
      nextMaxId = p.nextMaxId;
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      if (msg === 'unauthorized') {
        clearToken();
        goto('/');
        return;
      }
      error = msg === 'not_found' ? 'このリストは、見つかりませんでした。' : 'うまく届きませんでした。';
    } finally {
      loading = false;
      initial = false;
    }
  }

  async function loadMore() {
    if (loading) return;
    loading = true;
    try {
      const p = await fetchListTimeline(id, { maxId: nextMaxId });
      items = [...items, ...p.items];
      nextMaxId = p.nextMaxId;
    } catch {
      // 続きが取れなかったら静かに止める。
    } finally {
      loading = false;
    }
  }

  function onMembersToggle(e: Event) {
    if ((e.currentTarget as HTMLDetailsElement).open && !membersLoaded) void loadMembers();
  }

  async function loadMembers() {
    try {
      members = await getListAccounts(id);
      membersLoaded = true;
    } catch {
      // 静かに止める。開き直せばまた試す。
    }
  }

  async function addMember() {
    const acct = addAcct.trim().replace(/^@/, '');
    if (!acct || addPending) return;
    addPending = true;
    addError = null;
    try {
      const a = await lookupAccount(acct);
      await addToList(id, [a.id]);
      if (!members.some((m) => m.id === a.id)) members = [...members, a];
      addAcct = '';
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      addError = msg === 'not_found' ? 'その人は、見つかりませんでした。' : '追加できませんでした。';
    } finally {
      addPending = false;
    }
  }

  async function removeMember(a: Account) {
    try {
      await removeFromList(id, [a.id]);
      members = members.filter((m) => m.id !== a.id);
    } catch {
      // 失敗時はそのまま。
    }
  }
</script>

<header
  class="timeline"
  style="display: flex; justify-content: space-between; align-items: baseline; gap: var(--space-3);"
>
  <h1 style="font-size: var(--text-lg);">{list?.title ?? 'リスト'}</h1>
  <a class="chip" href="/lists">リスト一覧</a>
</header>

{#if error}
  <p class="error timeline">{error}</p>
  <p class="timeline"><a class="chip" href="/lists">リスト一覧へ</a></p>
{:else}
  <details class="timeline" ontoggle={onMembersToggle} style="margin-bottom: var(--space-4);">
    <summary style="cursor: pointer;">メンバー</summary>

    <form
      onsubmit={(e) => {
        e.preventDefault();
        void addMember();
      }}
      style="display: flex; gap: var(--space-2); margin: var(--space-3) 0;"
    >
      <input
        type="text"
        bind:value={addAcct}
        placeholder="@user または @user@host"
        style="flex: 1;"
      />
      <button type="submit" disabled={addPending || !addAcct.trim()}>加える</button>
    </form>

    {#if addError}
      <p class="error">{addError}</p>
    {/if}

    {#if membersLoaded && members.length === 0}
      <p class="prose-small">まだ、だれも入っていません。</p>
    {/if}
    {#each members as a (a.id)}
      <AccountActionRow account={a} actionLabel="外す" onaction={removeMember} />
    {/each}
  </details>

  <section class="timeline">
    {#if initial && loading}
      <p class="loading">読んでいます…</p>
    {:else if items.length === 0 && !loading}
      <p class="prose-small">
        このリストには、まだ何も流れていません。メンバーを加えると、ここに集まります。
      </p>
    {/if}

    {#each items as s (s.id)}
      <StatusCard
        status={s}
        canReply
        ondelete={(d) => (items = items.filter((it) => it.id !== d.id))}
      />
    {/each}

    {#if !initial && loading}
      <p class="loading">読んでいます…</p>
    {/if}

    {#if nextMaxId && !loading}
      <button class="load-more" onclick={loadMore}>もっと読む</button>
    {/if}
  </section>
{/if}
