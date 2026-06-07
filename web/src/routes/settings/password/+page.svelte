<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { isLoggedIn, clearToken, changePassword } from '$lib/auth';
  import { verifyCredentials } from '$lib/api';
  import { t } from '$lib/i18n';

  let username = $state('');
  let current = $state('');
  let nextPw = $state('');
  let confirm = $state('');
  let error = $state<string | null>(null);
  let submitting = $state(false);
  let done = $state(false);

  onMount(async () => {
    if (!isLoggedIn()) {
      void goto('/');
      return;
    }
    // tagline に @id を出すためだけに引く。取れなくても変更は進められる。
    try {
      const me = await verifyCredentials();
      username = me.username ?? me.acct ?? '';
    } catch {
      /* tagline は空のままでよい */
    }
  });

  async function submit() {
    if (submitting) return;
    if (nextPw !== confirm) {
      error = $t('password.errMismatch');
      return;
    }
    submitting = true;
    error = null;
    try {
      await changePassword(current, nextPw, confirm);
      // 成功でサーバが全セッションを失効させる。手元の OAuth トークンも
      // もう用済みなので落として、入りなおしてもらう。
      clearToken();
      done = true;
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      error =
        msg === 'current'
          ? $t('password.errCurrent')
          : msg === 'mismatch'
            ? $t('password.errMismatch')
            : msg === 'short'
              ? $t('password.errShort')
              : msg === 'unauthorized'
                ? $t('password.errAuth')
                : $t('password.failed');
      submitting = false;
    }
  }
</script>

{#if done}
  <section class="hero">
    <h1>{$t('password.doneTitle')}</h1>
  </section>
  <p class="notice">{$t('password.doneNotice')}</p>
  <p><a class="chip" href="/login">{$t('login.title')}</a></p>
{:else}
  <section class="hero">
    <h1>{$t('password.title')}</h1>
    {#if username}<p class="tagline">{$t('password.tagline', { username })}</p>{/if}
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
      <span>{$t('password.current')}</span>
      <input type="password" bind:value={current} autocomplete="current-password" required />
    </label>
    <label class="stack-tight">
      <span>{$t('password.new')}</span>
      <input type="password" bind:value={nextPw} autocomplete="new-password" minlength="8" required />
    </label>
    <label class="stack-tight">
      <span>{$t('password.confirm')}</span>
      <input
        type="password"
        bind:value={confirm}
        autocomplete="new-password"
        minlength="8"
        required
      />
    </label>
    <button type="submit" disabled={submitting}>{$t('password.submit')}</button>
  </form>

  <p class="prose-small"><a href="/settings">{$t('password.back')}</a></p>
{/if}
