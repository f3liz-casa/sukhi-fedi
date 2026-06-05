<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import {
    verifyCredentials,
    updateCredentials,
    getBlocks,
    getMutes,
    unblockAccount,
    unmuteAccount,
    type Account
  } from '$lib/api';
  import { clearToken, isLoggedIn, loadToken } from '$lib/auth';
  import AccountActionRow from '$lib/components/AccountActionRow.svelte';

  let me = $state<Account | null>(null);
  // admin の「管理ページへ」ボタンが /admin/login に POST する bearer。
  // SPA がすでに持っている OAuth トークンをそのまま渡すので、トークンを
  // 貼り直す手間が要らない。
  let adminToken = $state('');
  let displayName = $state('');
  let note = $state('');
  let locked = $state(false);
  let avatarFile = $state<File | null>(null);
  let headerFile = $state<File | null>(null);

  // 選んだファイルのプレビュー URL。$derived で作って、変わるたびに前のを revoke。
  let avatarPreview = $state<string | null>(null);
  let headerPreview = $state<string | null>(null);

  $effect(() => {
    if (!avatarFile) {
      avatarPreview = null;
      return;
    }
    const url = URL.createObjectURL(avatarFile);
    avatarPreview = url;
    return () => URL.revokeObjectURL(url);
  });

  $effect(() => {
    if (!headerFile) {
      headerPreview = null;
      return;
    }
    const url = URL.createObjectURL(headerFile);
    headerPreview = url;
    return () => URL.revokeObjectURL(url);
  });

  let loading = $state(true);
  let saving = $state(false);
  let error = $state<string | null>(null);
  let saved = $state(false);

  onMount(() => {
    if (!isLoggedIn()) {
      void goto('/');
      return;
    }
    void load();
  });

  async function load() {
    loading = true;
    error = null;
    try {
      me = await verifyCredentials();
      adminToken = loadToken()?.access_token ?? '';
      displayName = me.display_name ?? '';
      // note は HTML で返ってくる。編集はテキストとして扱いたいので、
      // 雑だけど <br> を改行、その他のタグを落とす最小処理。
      // 自分が前に入れた素のテキストに近づけるだけで、サーバが正本。
      note = stripTags(me.note ?? '');
      locked = !!me.locked;
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      if (msg === 'unauthorized') {
        clearToken();
        void goto('/');
        return;
      }
      error = 'うまく読めませんでした。';
    } finally {
      loading = false;
    }
  }

  function stripTags(html: string): string {
    return html
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/p>\s*<p>/gi, '\n\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'");
  }

  function onAvatar(ev: Event) {
    const input = ev.currentTarget as HTMLInputElement;
    avatarFile = input.files?.[0] ?? null;
  }

  function onHeader(ev: Event) {
    const input = ev.currentTarget as HTMLInputElement;
    headerFile = input.files?.[0] ?? null;
  }

  // ── ブロック / ミュート管理 ──────────────────────────────────────────
  // <details> を開いたとき一度だけ読む。サーバは全件返すのでページング無し。
  let blocks = $state<Account[]>([]);
  let mutes = $state<Account[]>([]);
  let relLoaded = $state(false);
  let relLoading = $state(false);
  let relError = $state<string | null>(null);

  function onRelToggle(e: Event) {
    if ((e.currentTarget as HTMLDetailsElement).open) void loadRelations();
  }

  async function loadRelations() {
    if (relLoaded || relLoading) return;
    relLoading = true;
    relError = null;
    try {
      const [b, m] = await Promise.all([getBlocks(), getMutes()]);
      blocks = b;
      mutes = m;
      relLoaded = true;
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      if (msg === 'unauthorized') {
        clearToken();
        void goto('/');
        return;
      }
      relError = 'うまく読めませんでした。';
    } finally {
      relLoading = false;
    }
  }

  async function doUnblock(a: Account) {
    try {
      await unblockAccount(a.id);
      blocks = blocks.filter((x) => x.id !== a.id);
    } catch {
      // 失敗時はそのまま。開き直して押し直せる。
    }
  }

  async function doUnmute(a: Account) {
    try {
      await unmuteAccount(a.id);
      mutes = mutes.filter((x) => x.id !== a.id);
    } catch {
      // 失敗時はそのまま。
    }
  }

  async function save() {
    if (!me || saving) return;
    saving = true;
    error = null;
    saved = false;
    try {
      const updated = await updateCredentials({
        display_name: displayName,
        note,
        locked,
        avatar: avatarFile,
        header: headerFile
      });
      me = updated;
      avatarFile = null;
      headerFile = null;
      saved = true;
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      if (msg === 'unauthorized') {
        clearToken();
        void goto('/');
        return;
      }
      error = 'うまく保存できませんでした。';
    } finally {
      saving = false;
    }
  }
</script>

<header class="timeline" style="display: flex; justify-content: space-between; align-items: baseline;">
  <h1 style="font-size: var(--text-lg);">設定</h1>
  <a class="chip" href="/timeline">戻る</a>
</header>

{#if loading}
  <p class="loading">読んでいます…</p>
{:else if me}
  <form
    class="settings-form"
    onsubmit={(e) => {
      e.preventDefault();
      void save();
    }}
  >
    <p class="muted">@{me.acct}</p>

    <label class="stack-tight">
      <span>表示名</span>
      <input type="text" bind:value={displayName} maxlength="30" />
    </label>

    <label class="stack-tight">
      <span>自己紹介</span>
      <textarea bind:value={note} rows="4" maxlength="500"></textarea>
    </label>

    <label class="stack-tight">
      <span>{avatarPreview ? '新しいアイコン（保存前）' : 'いまのアイコン'}</span>
      {#if avatarPreview}
        <img class="avatar avatar-lg" src={avatarPreview} alt="" />
      {:else if me.avatar}
        <img class="avatar avatar-lg" src={me.avatar} alt="" />
      {/if}
      <input type="file" accept="image/*" onchange={onAvatar} />
    </label>

    <label class="stack-tight">
      <span>{headerPreview ? '新しいヘッダ画像（保存前）' : 'いまのヘッダ画像'}</span>
      {#if headerPreview}
        <img class="profile-header" src={headerPreview} alt="" />
      {:else if me.header}
        <img class="profile-header" src={me.header} alt="" />
      {/if}
      <input type="file" accept="image/*" onchange={onHeader} />
    </label>

    <label class="stack-tight">
      <input type="checkbox" bind:checked={locked} />
      <span>フォローを、承認してから受ける（鍵）</span>
    </label>

    <div style="display: flex; gap: var(--space-3); align-items: center;">
      <button type="submit" disabled={saving}>
        {saving ? '保存しています…' : '保存'}
      </button>
      {#if saved}
        <span class="muted">保存しました。</span>
      {/if}
    </div>

    {#if error}
      <p class="error">{error}</p>
    {/if}
  </form>

  <details class="rel-manage" style="margin-top: var(--space-5);" ontoggle={onRelToggle}>
    <summary style="font-size: var(--text-md); cursor: pointer;">ブロック・ミュート</summary>

    {#if relLoading}
      <p class="loading">読んでいます…</p>
    {:else if relError}
      <p class="error">{relError}</p>
    {:else if relLoaded}
      <h2 style="font-size: var(--text-sm); margin-top: var(--space-3);">ブロック中</h2>
      {#if blocks.length === 0}
        <p class="prose-small">いません。</p>
      {:else}
        {#each blocks as a (a.id)}
          <AccountActionRow account={a} actionLabel="解除" onaction={doUnblock} />
        {/each}
      {/if}

      <h2 style="font-size: var(--text-sm); margin-top: var(--space-4);">ミュート中</h2>
      {#if mutes.length === 0}
        <p class="prose-small">いません。</p>
      {:else}
        {#each mutes as a (a.id)}
          <AccountActionRow account={a} actionLabel="解除" onaction={doUnmute} />
        {/each}
      {/if}
    {/if}
  </details>

  {#if me.role?.name === 'admin' && adminToken}
    <!-- /admin は別ドア(bearer 貼り付けログイン)。SPA が持っている
         トークンをそのまま POST して、貼り直しなしで入れるようにする。
         通常のリンクではなく form なのは、/admin/login が token を
         body で受けて session cookie を立てて 302 する作りだから。 -->
    <section class="admin-entry" style="margin-top: var(--space-5);">
      <h2 style="font-size: var(--text-md);">管理</h2>
      <p class="muted">このインスタンスの管理ページに入れます。</p>
      <form method="post" action="/admin/login">
        <input type="hidden" name="token" value={adminToken} />
        <button type="submit" class="chip">管理ページへ</button>
      </form>
    </section>
  {/if}
{/if}

<footer class="muted" style="margin-top: var(--space-6); font-size: var(--text-sm);">
  絵文字は <a href="https://github.com/jdecked/twemoji" target="_blank" rel="noopener noreferrer">Twemoji</a>（<a
    href="https://creativecommons.org/licenses/by/4.0/"
    target="_blank"
    rel="noopener noreferrer">CC-BY 4.0</a
  >）。
</footer>
