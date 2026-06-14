<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import {
    lookupAccount,
    getAccountStatuses,
    getRelationships,
    verifyCredentials,
    blockAccount,
    unblockAccount,
    muteAccount,
    unmuteAccount,
    type Account,
    type Relationship,
    type Status
  } from '$lib/api';
  import { isLoggedIn, clearToken } from '$lib/auth';
  import StatusCard from '$lib/components/Status.svelte';
  import Avatar from '$lib/components/Avatar.svelte';
  import FollowButton from '$lib/components/FollowButton.svelte';
  import AddToListButton from '$lib/components/AddToListButton.svelte';
  import Composer from '$lib/components/Composer.svelte';
  import Twemoji from '$lib/components/Twemoji.svelte';
  import { phrase } from '$lib/phrase';
  import { renderEmojis } from '$lib/emoji';
  import { t } from '$lib/i18n';

  let account = $state<Account | null>(null);
  let me = $state<Account | null>(null);
  let rel = $state<Relationship | null>(null);
  let items = $state<Status[]>([]);
  let pinnedItems = $state<Status[]>([]);
  let nextMaxId = $state<string | null>(null);
  let loading = $state(false);
  let error = $state<string | null>(null);
  let initial = $state(true);

  // 記事（Article）を持つ人にだけ、プロフィールに「記事」タブを出す。
  // 読み込み時に一度だけ記事を引いて、あればタブを立てる。
  let tab = $state<'posts' | 'articles'>('posts');
  let articleItems = $state<Status[]>([]);
  let articleNextMaxId = $state<string | null>(null);
  let hasArticles = $derived(articleItems.length > 0);

  let acct = $derived($page.params.acct ?? '');
  let isSelf = $derived(!!account && !!me && me.id === account.id);

  // プロフィール上の投稿にも、その場で返信できるように。返信先の公開範囲は
  // Composer が引き継ぐ。送れたら自分のプロフィールを見ているとき(=自分への
  // 返信は稀)だけ先頭に足す、ということはせず、素直に閉じるだけにする。
  let replyTo = $state<Status | null>(null);
  let composerOpen = $state(false);

  function onReply(s: Status) {
    replyTo = s;
    composerOpen = true;
    if (typeof window !== 'undefined') window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function onPosted() {
    composerOpen = false;
    replyTo = null;
  }

  function onCancel() {
    composerOpen = false;
    replyTo = null;
  }

  // ピン留め欄でピンを外したら、その場で欄から外す。
  function onPinUpdate(s: Status) {
    if (!s.pinned) pinnedItems = pinnedItems.filter((it) => it.id !== s.id);
  }

  // ブロック / ミュート。relationship を握り直して表示に反映する。
  let modPending = $state(false);
  let menuOpen = $state(false);

  async function toggleBlock() {
    if (!account || modPending) return;
    modPending = true;
    try {
      rel = rel?.blocking ? await unblockAccount(account.id) : await blockAccount(account.id);
    } catch {
      // 失敗は黙って戻す(rel はそのまま)。
    } finally {
      modPending = false;
      menuOpen = false;
    }
  }

  async function toggleMute() {
    if (!account || modPending) return;
    modPending = true;
    try {
      rel = rel?.muting ? await unmuteAccount(account.id) : await muteAccount(account.id);
    } catch {
      // 同上。
    } finally {
      modPending = false;
      menuOpen = false;
    }
  }

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
      const empty = { items: [] as Status[], nextMaxId: null };
      const [page1, pins, articles] = await Promise.all([
        getAccountStatuses(account.id),
        // ピン留めは featured collection。取れなくてもプロフィール本体は出す。
        getAccountStatuses(account.id, { pinned: true }).catch(() => empty),
        // 記事タブの種。あればタブを出す。無ければ静かに空のまま。
        getAccountStatuses(account.id, { articles: true }).catch(() => empty)
      ]);
      items = page1.items;
      nextMaxId = page1.nextMaxId;
      articleItems = articles.items;
      articleNextMaxId = articles.nextMaxId;
      // featured 由来＝定義上ピン留め済み。サーバの viewer flag を待たず
      // フラグを立て、メニューが「外す」を出せるようにする。
      pinnedItems = pins.items.map((s) => ({ ...s, pinned: true }));
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      if (msg === 'unauthorized') {
        clearToken();
        void goto('/');
        return;
      }
      if (msg === 'not_found') {
        error = $t('common.acctNotFound', { acct });
      } else {
        error = $t('common.deliverFailed');
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

  async function loadMoreArticles() {
    if (!account || loading) return;
    loading = true;
    try {
      const p = await getAccountStatuses(account.id, { articles: true, maxId: articleNextMaxId });
      articleItems = [...articleItems, ...p.items];
      articleNextMaxId = p.nextMaxId;
    } catch {
      // 同上、静かに止める。
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
{:else if account}
  <header class="profile-head">
    {#if account.header}
      <img class="profile-header" src={account.header} alt="" loading="lazy" />
    {/if}
    <div class="profile-id">
      <Avatar class="avatar avatar-lg" src={account.avatar} name={account.display_name || account.username} />
      <div class="stack-tight" style="flex: 1;">
        <p class="display-name" style="font-size: var(--text-lg);">
          {@html renderEmojis(phrase(account.display_name || account.username), account.emojis)}
        </p>
        <p class="muted">@{account.acct}</p>
      </div>
      {#if isSelf}
        <a class="chip" href="/settings">{$t('profile.edit')}</a>
      {:else}
        <div class="profile-actions">
          <FollowButton accountId={account.id} relationship={rel} onchange={(r) => (rel = r)} />
        {#if rel}
          <AddToListButton accountId={account.id} />
        {/if}
        {#if rel}
          <div class="mod-menu">
            <button
              type="button"
              class="chip"
              aria-haspopup="menu"
              aria-expanded={menuOpen}
              onclick={() => (menuOpen = !menuOpen)}>…</button
            >
            {#if menuOpen}
              <div class="mod-menu-pop" role="menu">
                <button type="button" role="menuitem" onclick={toggleMute} disabled={modPending}>
                  {rel.muting ? $t('profile.unmute') : $t('profile.mute')}
                </button>
                <button
                  type="button"
                  role="menuitem"
                  class="danger"
                  onclick={toggleBlock}
                  disabled={modPending}
                >
                  {rel.blocking ? $t('profile.unblock') : $t('profile.block')}
                </button>
              </div>
            {/if}
          </div>
        {/if}
        </div>
      {/if}
    </div>

    {#if account.note}
      <div class="profile-note">{@html renderEmojis(account.note, account.emojis)}</div>
    {/if}

    <p class="profile-counts">
      <a href={`/@${account.acct}/following`}>
        <strong>{account.following_count ?? 0}</strong> {$t('profile.followingSuffix')}
      </a>
      <a href={`/@${account.acct}/followers`}>
        <strong>{account.followers_count ?? 0}</strong> {$t('profile.followersSuffix')}
      </a>
      <span><strong>{account.statuses_count ?? 0}</strong> {$t('profile.postsSuffix')}</span>
    </p>
  </header>

  {#if composerOpen}
    <Composer {replyTo} prefillMention={!!replyTo} onposted={onPosted} oncancel={onCancel} />
  {/if}

  {#if hasArticles}
    <!-- 記事を持つ人だけ、投稿と記事を分けて見られるように。 -->
    <nav class="profile-tabs" aria-label={$t('profile.tabsLabel')}>
      <button class="tab" class:active={tab === 'posts'} onclick={() => (tab = 'posts')}>
        {$t('profile.tabPosts')}
      </button>
      <button class="tab" class:active={tab === 'articles'} onclick={() => (tab = 'articles')}>
        {$t('profile.tabArticles')}
      </button>
    </nav>
  {/if}

  {#if tab === 'articles'}
    <section class="timeline">
      {#each articleItems as s (s.id)}
        <StatusCard
          status={s}
          canReply
          onreply={onReply}
          ondelete={(d) => (articleItems = articleItems.filter((it) => it.id !== d.id))}
        />
      {/each}

      {#if articleNextMaxId && !loading}
        <button class="load-more" onclick={loadMoreArticles}>{$t('common.loadMore')}</button>
      {/if}
    </section>
  {:else}
    {#if pinnedItems.length > 0}
      <section class="timeline pinned">
        <p class="pinned-label"><Twemoji emoji="📌" /> {$t('profile.pinned')}</p>
        {#each pinnedItems as s (s.id)}
          <StatusCard
            status={s}
            canReply
            onreply={onReply}
            onupdate={onPinUpdate}
            ondelete={(d) => (pinnedItems = pinnedItems.filter((it) => it.id !== d.id))}
          />
        {/each}
      </section>
    {/if}

    <section class="timeline">
      {#if items.length === 0 && !loading}
        <p class="prose-small">{$t('profile.empty')}</p>
      {/if}

      {#each items as s (s.id)}
        <StatusCard
          status={s}
          canReply
          onreply={onReply}
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
{/if}

<style>
  /* フォロー/リスト追加/… を一塊にして、狭い幅では折り返す（モバイルで
     横に溢れないように）。avatar + 名前の右に寄せる。 */
  .profile-actions {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex-wrap: wrap;
    justify-content: flex-end;
    margin-left: auto;
  }
  .mod-menu {
    position: relative;
    display: inline-block;
  }
  .mod-menu-pop {
    position: absolute;
    right: 0;
    top: calc(100% + 0.25rem);
    z-index: 10;
    display: flex;
    flex-direction: column;
    min-width: 10rem;
    padding: 0.25rem;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    background: var(--color-surface);
  }
  .mod-menu-pop button {
    text-align: left;
    padding: 0.5rem 0.625rem;
    background: none;
    border: none;
    border-radius: var(--radius-sm);
    cursor: pointer;
  }
  .mod-menu-pop button:hover:not(:disabled) {
    background: var(--fill-hover);
  }
  .mod-menu-pop button.danger {
    color: #dc2626;
  }
  .pinned-label {
    font-size: var(--text-sm);
    color: var(--color-text-muted);
  }

  /* 投稿 / 記事 の切り替え。控えめに、下線で今いる場所だけ示す。 */
  .profile-tabs {
    display: flex;
    gap: var(--space-1);
    border-bottom: 1px solid var(--color-border);
  }
  .profile-tabs .tab {
    padding: 0.5rem 0.9rem;
    background: none;
    border: none;
    border-bottom: 2px solid transparent;
    margin-bottom: -1px;
    color: var(--color-text-muted);
    cursor: pointer;
  }
  .profile-tabs .tab.active {
    color: var(--color-text);
    border-bottom-color: var(--color-text);
  }
</style>
