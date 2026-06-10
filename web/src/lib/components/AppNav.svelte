<script lang="ts">
  // ログイン後の全ページにかかる共通ヘッダー。wordmark を左に、
  // 行き先の chip を右に。これが入ったので、各ページの
  // 「← タイムライン」往復リンクは持たない。
  //
  // ログイン状態は localStorage なので、mount 時とページ遷移のたびに
  // 見直す ─ ログイン直後・ログアウト直後の画面でも正しく出入りする。
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import { goto, afterNavigate } from '$app/navigation';
  import { isLoggedIn, signOutServer } from '$lib/auth';
  import { requestCompose } from '$lib/compose';
  import { t } from '$lib/i18n';

  let loggedIn = $state(false);

  onMount(() => {
    loggedIn = isLoggedIn();
  });

  afterNavigate(() => {
    loggedIn = isLoggedIn();
  });

  const links = [
    { href: '/notifications', key: 'nav.notifications' },
    { href: '/messages', key: 'nav.messages' },
    { href: '/search', key: 'nav.search' },
    { href: '/bookmarks', key: 'nav.bookmarks' },
    { href: '/favourites', key: 'nav.favourites' },
    { href: '/lists', key: 'nav.lists' },
    { href: '/settings', key: 'nav.settings' }
  ] as const;

  async function compose() {
    if (page.url.pathname !== '/timeline') await goto('/timeline');
    requestCompose();
  }

  async function signOut() {
    await signOutServer();
    loggedIn = false;
    goto('/');
  }
</script>

{#if loggedIn}
  <header class="app-nav">
    <div class="wrap app-nav-row">
      <a class="app-nav-name" href="/timeline">sukhi-fedi</a>
      <nav class="page-nav" aria-label={$t('nav.label')}>
        <button class="chip" onclick={compose}>{$t('nav.compose')}</button>
        {#each links as l (l.href)}
          <a
            class="chip"
            href={l.href}
            aria-current={page.url.pathname === l.href ? 'page' : undefined}
          >{$t(l.key)}</a>
        {/each}
        <button class="chip" onclick={signOut}>{$t('nav.logout')}</button>
      </nav>
    </div>
  </header>
{/if}
