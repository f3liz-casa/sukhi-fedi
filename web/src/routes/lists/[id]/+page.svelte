<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import {
    getList,
    fetchListTimeline,
    getListAccounts,
    getRelationships,
    addToList,
    removeFromList,
    lookupAccount,
    type List,
    type Status,
    type Account,
    type Relationship
  } from '$lib/api';
  import { isLoggedIn, clearToken } from '$lib/auth';
  import StatusCard from '$lib/components/Status.svelte';
  import TimelineFilter from '$lib/components/TimelineFilter.svelte';
  import AccountActionRow from '$lib/components/AccountActionRow.svelte';
  import { t } from '$lib/i18n';
  import { refreshCircles } from '$lib/circles';

  let id = $derived($page.params.id ?? '');

  let list = $state<List | null>(null);
  let items = $state<Status[]>([]);
  let nextMaxId = $state<string | null>(null);
  let loading = $state(false);
  let initial = $state(true);
  let error = $state<string | null>(null);

  // 表示フィルター（タイムラインと同じ。リストはブーストを混ぜないので RT 隠しは無し）。
  let onlyMedia = $state(false);
  let hideSensitive = $state(false);

  // メンバー（<details> を開いたとき一度だけ読む）。
  let members = $state<Account[]>([]);
  let membersLoaded = $state(false);
  // メンバーごとの relationship（フォロー状態）。取れなくても表示は進める。
  let rels = $state<Record<string, Relationship>>({});

  // 未フォローのメンバーが居たら「フォローすると流れる」ヒントを一度出す。
  let hasUnfollowed = $derived(
    members.some((m) => {
      const r = rels[m.id];
      return r && !r.following && !r.requested;
    })
  );
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
      const p = await fetchListTimeline(id, { onlyMedia, hideSensitive });
      items = p.items;
      nextMaxId = p.nextMaxId;
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      if (msg === 'unauthorized') {
        clearToken();
        goto('/');
        return;
      }
      error = msg === 'not_found' ? $t('listDetail.notFound') : $t('common.deliverFailed');
    } finally {
      loading = false;
      initial = false;
    }
  }

  async function loadMore() {
    if (loading) return;
    loading = true;
    try {
      const p = await fetchListTimeline(id, { maxId: nextMaxId, onlyMedia, hideSensitive });
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
      await loadRels(members.map((m) => m.id));
      membersLoaded = true;
    } catch {
      // 静かに止める。開き直せばまた試す。
    }
  }

  // メンバーの relationship をまとめて引いて rels に重ねる。フォロー状態が
  // 取れなくても（失敗しても）名簿としての表示は止めない。
  async function loadRels(ids: string[]) {
    if (ids.length === 0) return;
    try {
      const rs = await getRelationships(ids);
      const next = { ...rels };
      for (const r of rs) next[r.id] = r;
      rels = next;
    } catch {
      // フォロー状態が無くても、サークルは成立する。
    }
  }

  // FollowButton が返した最新の relationship を反映（ヒントの出し分けに効く）。
  function onFollowChange(r: Relationship) {
    rels = { ...rels, [r.id]: r };
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
      await loadRels([a.id]);
      void refreshCircles();
      addAcct = '';
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      addError = msg === 'not_found' ? $t('listDetail.notFoundPerson') : $t('listDetail.addFailed');
    } finally {
      addPending = false;
    }
  }

  async function removeMember(a: Account) {
    try {
      await removeFromList(id, [a.id]);
      members = members.filter((m) => m.id !== a.id);
      void refreshCircles();
    } catch {
      // 失敗時はそのまま。
    }
  }

  // フィルターを変えたらタイムラインを読み直す。
  function applyFilters() {
    void load();
  }
</script>

<p class="back-row timeline"><a class="back-link" href="/lists">← {$t('listDetail.listIndex')}</a></p>
<header class="timeline page-head">
  <h1>{list?.title ?? $t('listDetail.fallbackTitle')}</h1>
</header>

{#if error}
  <p class="error timeline">{error}</p>
  <p class="timeline"><a class="chip" href="/lists">{$t('listDetail.toListIndex')}</a></p>
{:else}
  <details class="timeline" ontoggle={onMembersToggle} style="margin-bottom: var(--space-4);">
    <summary style="cursor: pointer;">{$t('listDetail.members')}</summary>

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
        placeholder={$t('listDetail.addPlaceholder')}
        style="flex: 1;"
      />
      <button type="submit" disabled={addPending || !addAcct.trim()}>{$t('listDetail.add')}</button>
    </form>

    {#if addError}
      <p class="error">{addError}</p>
    {/if}

    {#if membersLoaded && members.length === 0}
      <p class="prose-small">{$t('listDetail.noMembers')}</p>
    {/if}
    {#if hasUnfollowed}
      <p class="prose-small">{$t('listDetail.followHint')}</p>
    {/if}
    {#each members as a (a.id)}
      <AccountActionRow
        account={a}
        actionLabel={$t('listDetail.removeMember')}
        onaction={removeMember}
        relationship={rels[a.id] ?? null}
        onfollowchange={onFollowChange}
      />
    {/each}
  </details>

  <div class="timeline">
    <TimelineFilter bind:onlyMedia bind:hideSensitive onchange={applyFilters} />
  </div>

  <section class="timeline">
    {#if initial && loading}
      <p class="loading">{$t('common.loading')}</p>
    {:else if items.length === 0 && !loading}
      <p class="prose-small">
        {$t('listDetail.empty')}
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
      <p class="loading">{$t('common.loading')}</p>
    {/if}

    {#if nextMaxId && !loading}
      <button class="load-more" onclick={loadMore}>{$t('common.loadMore')}</button>
    {/if}
  </section>
{/if}
