<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import { isLoggedIn, loginWithPassword } from '$lib/auth';
  import { t } from '$lib/i18n';
  import LangSwitch from '$lib/components/LangSwitch.svelte';

  let username = $state('');
  let password = $state('');
  let error = $state<string | null>(null);
  let submitting = $state(false);

  // /oauth/authorize から未ログインで弾かれてきたときは ?next に元の
  // authorize URL が入っている。ホームの「入る」から来たときは next が
  // 無いので、Anubis の通り道 /check?intent=login を既定にする。
  let next = $derived.by(() => {
    const n = $page.url.searchParams.get('next');
    return n && n.startsWith('/') ? n : '/check?intent=login';
  });

  onMount(() => {
    if (isLoggedIn()) void goto('/timeline');
  });

  async function submit() {
    if (submitting) return;
    submitting = true;
    error = null;
    try {
      await loginWithPassword(username, password);
      // セッションクッキーが立った。next(=/check か /oauth/authorize)へは
      // フルリロードで渡す ─ /check は Anubis の challenge を、authorize は
      // サーバ描画を、それぞれ通す必要があるから SPA ナビでは抜けられない。
      window.location.assign(next);
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      error = msg === 'invalid' ? $t('login.invalid') : $t('login.failed');
      submitting = false;
    }
  }
</script>

<section class="hero">
  <h1>{$t('login.title')}</h1>
  <p class="tagline">{$t('login.tagline')}</p>
</section>

{#if error}
  <p class="error">{error}</p>
{/if}

<form
  class="form stack"
  onsubmit={(e) => {
    e.preventDefault();
    void submit();
  }}
>
  <label class="stack-tight">
    <span>{$t('login.id')}</span>
    <input
      type="text"
      bind:value={username}
      autocomplete="username"
      autocapitalize="none"
      autocorrect="off"
      spellcheck="false"
      required
    />
  </label>

  <label class="stack-tight">
    <span>{$t('login.password')}</span>
    <input type="password" bind:value={password} autocomplete="current-password" required />
  </label>

  <button type="submit" disabled={submitting}>{$t('login.submit')}</button>
</form>

<p class="prose-small"><a href="/signup">{$t('login.toSignup')}</a></p>
<p class="prose-small"><a href="/">{$t('signup.backToFront')}</a></p>

<section class="section" style="text-align: center; margin-top: var(--space-5);">
  <LangSwitch />
</section>
