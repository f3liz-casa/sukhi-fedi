<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import {
    verifyCredentials,
    updateCredentials,
    type Account
  } from '$lib/api';
  import { clearToken, isLoggedIn } from '$lib/auth';

  let me = $state<Account | null>(null);
  let displayName = $state('');
  let note = $state('');
  let locked = $state(false);
  let avatarFile: File | null = null;
  let headerFile: File | null = null;

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
      <span>いまのアイコン</span>
      {#if me.avatar}
        <img class="avatar avatar-lg" src={me.avatar} alt="" />
      {/if}
      <input type="file" accept="image/*" onchange={onAvatar} />
    </label>

    <label class="stack-tight">
      <span>いまのヘッダ画像</span>
      {#if me.header}
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
{/if}
