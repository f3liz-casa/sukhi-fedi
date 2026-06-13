<script lang="ts">
  // ログイン後の全ページにかかる共通ヘッダー。wordmark を左に、
  // 行き先の chip を右に。これが入ったので、各ページの
  // 「← タイムライン」往復リンクは持たない。
  //
  // ログイン状態は localStorage なので、mount 時とページ遷移のたびに
  // 見直す ─ ログイン直後・ログアウト直後の画面でも正しく出入りする。
  //
  // 通知 chip にはふたつの層がのる(lib/notify.ts):
  //   direct(返信・DM・フォロー申請)= 数をそのまま。SSE で即。
  //   ambient(お気に入りなど)= NotifGlyph の育つかたち。遷移の
  //   境界でだけ数えなおすので、目の前で育つことはない。
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import { goto, afterNavigate } from '$app/navigation';
  import { isLoggedIn, signOutServer } from '$lib/auth';
  import { requestCompose } from '$lib/compose';
  import {
    directUnseen,
    ambientUnseen,
    refreshUnseen,
    startStream,
    stopStream
  } from '$lib/notify';
  import NotifGlyph from '$lib/components/NotifGlyph.svelte';
  import { t } from '$lib/i18n';

  let loggedIn = $state(false);

  function sync() {
    loggedIn = isLoggedIn();
    if (loggedIn) {
      void refreshUnseen();
      startStream();
    } else {
      stopStream();
    }
  }

  onMount(() => {
    sync();
    return () => stopStream();
  });

  afterNavigate(() => {
    sync();
  });

  // 通知 chip は層の表示を持つので、ループの外で別に描く。
  const links = [
    { href: '/messages', key: 'nav.messages' },
    { href: '/search', key: 'nav.search' },
    { href: '/bookmarks', key: 'nav.bookmarks' },
    { href: '/favourites', key: 'nav.favourites' },
    { href: '/lists', key: 'nav.lists' },
    { href: '/settings', key: 'nav.settings' }
  ] as const;

  // 読み上げと hover には、かたちでなく言葉で正直に。
  const notifHint = $derived.by(() => {
    const parts: string[] = [];
    if ($directUnseen > 0) parts.push($t('nav.notifDirect', { n: $directUnseen }));
    if ($ambientUnseen > 0) parts.push($t('nav.notifAmbient'));
    return parts.length > 0 ? parts.join(' / ') : null;
  });

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
        <a
          class="chip"
          href="/notifications"
          aria-current={page.url.pathname === '/notifications' ? 'page' : undefined}
          aria-label={notifHint ? `${$t('nav.notifications')} — ${notifHint}` : undefined}
          title={notifHint ?? undefined}
        >
          {$t('nav.notifications')}{#if $directUnseen > 0}<span class="notif-count">{$directUnseen}</span
            >{/if}{#if $ambientUnseen > 0}<NotifGlyph count={$ambientUnseen} />{/if}
        </a>
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

<style>
  /* direct の数。バッジにしない — 赤も、丸も、ふくらみもなし。
     ただの数字が隣にいるだけ。色は chip の文字色に従う。 */
  .notif-count {
    margin-left: var(--space-1);
    font-variant-numeric: tabular-nums;
  }
</style>
