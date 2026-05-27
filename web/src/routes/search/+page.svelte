<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import {
    searchAll,
    getRelationships,
    type Account,
    type Relationship,
    type SearchResult,
    type Tag
  } from '$lib/api';
  import { clearToken, isLoggedIn } from '$lib/auth';
  import AccountRow from '$lib/components/AccountRow.svelte';

  let q = '';
  let pending = '';
  let result: SearchResult = { accounts: [], hashtags: [], statuses: [] };
  let relations = new Map<string, Relationship>();
  let loading = false;
  let error: string | null = null;
  let searched = false;
  // 「remote 解決中…」表示。WebFinger を踏むので結果が出るまで
  // 数秒待つことがある。
  let resolving = false;

  // URL の `?q=...` で初期化(リンクで飛ばれたとき)
  onMount(() => {
    if (!isLoggedIn()) {
      void goto('/');
      return;
    }
    const initial = $page.url.searchParams.get('q') ?? '';
    if (initial) {
      pending = initial;
      q = initial;
      void run();
    }
  });

  // remote 形式 (`@user@host` または `user@host`) のとき resolve=true。
  // local prefix だけのときは resolve は要らない(余計な WebFinger を
  // 蹴らないように)。
  function looksRemote(s: string): boolean {
    const bare = s.trim().replace(/^@/, '');
    return bare.includes('@');
  }

  async function run() {
    if (!q.trim()) return;
    loading = true;
    resolving = looksRemote(q);
    error = null;
    searched = true;
    relations = new Map();

    try {
      result = await searchAll(q, { resolve: looksRemote(q) });
      // 自分以外のアカウントに、その場でフォロー状態を当てる。
      const ids = result.accounts.map((a) => a.id);
      if (ids.length > 0) {
        try {
          const rs = await getRelationships(ids);
          relations = new Map(rs.map((r) => [r.id, r]));
        } catch {
          /* 関係性が取れなくても結果は出す */
        }
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      if (msg === 'unauthorized') {
        clearToken();
        void goto('/');
        return;
      }
      error = looksRemote(q)
        ? '遠くの人を、見つけられませんでした。サーバの綴りを、確かめてみてください。'
        : 'うまく探せませんでした。';
      result = { accounts: [], hashtags: [], statuses: [] };
    } finally {
      loading = false;
      resolving = false;
    }
  }

  function submit() {
    q = pending.trim();
    if (!q) return;
    // URL も更新しておくと、リロード・共有しやすい。
    const url = new URL(window.location.href);
    url.searchParams.set('q', q);
    history.replaceState(null, '', url);
    void run();
  }
</script>

<header
  class="timeline"
  style="display: flex; justify-content: space-between; align-items: baseline;"
>
  <h1 style="font-size: var(--text-lg);">さがす</h1>
  <a class="chip" href="/timeline">戻る</a>
</header>

<form class="form stack" on:submit|preventDefault={submit}>
  <label class="stack-tight">
    <span>名前、ID、または <code>@user@host</code> / <code>#tag</code></span>
    <input
      type="text"
      bind:value={pending}
      placeholder="例: alice / @alice@mastodon.social / #しずか"
      autocapitalize="none"
      autocorrect="off"
      spellcheck="false"
    />
  </label>
  <button type="submit" disabled={loading || !pending.trim()}>
    {loading ? (resolving ? '遠くまで、たずねています…' : '探しています…') : 'さがす'}
  </button>
</form>

{#if error}
  <p class="error">{error}</p>
{/if}

{#if searched && !loading && !error}
  {#if result.accounts.length === 0 && result.hashtags.length === 0}
    <p class="prose-small">
      「{q}」は、見つかりませんでした。
      {#if !looksRemote(q)}
        遠くの人なら、<code>@user@host</code> の形で書いてみてください。
      {/if}
    </p>
  {:else}
    {#if result.accounts.length > 0}
      <section class="account-list">
        <h2 class="muted" style="font-size: var(--text-sm); margin: var(--space-4) 0 var(--space-2);">
          ひと
        </h2>
        {#each result.accounts as a (a.id)}
          <AccountRow account={a} relationship={relations.get(a.id) ?? null} />
        {/each}
      </section>
    {/if}

    {#if result.hashtags.length > 0}
      <section
        class="account-list"
        style="margin-top: var(--space-6);"
      >
        <h2 class="muted" style="font-size: var(--text-sm); margin: var(--space-4) 0 var(--space-2);">
          タグ
        </h2>
        {#each result.hashtags as t (t.name)}
          <article class="account-row">
            <a class="account-row-link" href={`/timeline?tag=${encodeURIComponent(t.name)}`}>
              <span class="display-name">#{t.name}</span>
            </a>
          </article>
        {/each}
      </section>
    {/if}
  {/if}
{/if}
