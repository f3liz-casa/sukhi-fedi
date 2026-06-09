<script lang="ts">
  import { onMount } from 'svelte';
  import {
    goToCheck,
    saveSignupDraft,
    loadSignupDraft
  } from '$lib/auth';
  import { t, locale } from '$lib/i18n';
  import LangSwitch from '$lib/components/LangSwitch.svelte';

  let username = $state('');
  let password = $state('');
  let invite_code = $state('');
  let agreed = $state(false);
  let error = $state<string | null>(null);

  // Send the consent links to the legal page in the current UI language.
  const termsHref = $derived($locale === 'ko' ? '/terms?lang=ko' : '/terms');
  const privacyHref = $derived($locale === 'ko' ? '/privacy?lang=ko' : '/privacy');

  // /check で失敗して戻ってきた人のために下書きを復元するが、
  // password だけは(/check が clearSignupPassword で落としてあるので)
  // 復活しない。retry のときは合言葉だけもう一度打ってもらう。
  onMount(() => {
    const d = loadSignupDraft();
    if (d) {
      username = d.username ?? '';
      invite_code = d.invite_code ?? '';
      if (!d.password) {
        error = $t('signup.pwAgain');
      }
    }
  });

  function submit() {
    error = null;
    saveSignupDraft({ username, password, invite_code });
    goToCheck('signup');
  }

  // 「こちらから入れます」は /login(server)へ直接。下書きが残って
  // いると signup に戻ってきたとき紛らわしいので、ここでは消さない
  // ─ 下書きは sessionStorage なので、タブを閉じれば自然に消える。
</script>

<section class="hero">
  <h1>{$t('signup.title')}</h1>
  <p class="tagline">{$t('signup.tagline')}</p>
</section>

{#if error}
  <p class="error">{error}</p>
{/if}

<form
  class="form stack"
  onsubmit={(e) => {
    e.preventDefault();
    submit();
  }}
>
  <label class="stack-tight">
    <span>{$t('signup.id')}</span>
    <input
      type="text"
      bind:value={username}
      autocomplete="username"
      pattern="[a-z0-9_]{'{1,30}'}"
      title={$t('signup.idTitle')}
      required
    />
    <span class="help">{$t('signup.idHelpPre')}<code>usagi_05</code></span>
  </label>

  <label class="stack-tight">
    <span>{$t('signup.password')}</span>
    <input
      type="password"
      bind:value={password}
      autocomplete="new-password"
      minlength="8"
      required
    />
    <span class="help">{$t('signup.passwordHelp')}</span>
  </label>

  <label class="stack-tight">
    <span>{$t('signup.inviteCode')}</span>
    <input type="text" bind:value={invite_code} autocomplete="off" required />
  </label>

  <label class="agree">
    <input type="checkbox" bind:checked={agreed} required />
    <span
      >{$t('signup.agreePre')}<a href={termsHref} target="_blank" rel="noopener">{$t('signup.termsLink')}</a
      >{$t('signup.agreeMid')}<a href={privacyHref} target="_blank" rel="noopener">{$t('signup.privacyLink')}</a
      >{$t('signup.agreePost')}</span
    >
  </label>

  <button type="submit" disabled={!agreed}>{$t('signup.create')}</button>
</form>

<p class="prose-small">
  {$t('signup.haveAccountPre')}<a href="/login">{$t('signup.haveAccountLink')}</a>{$t('signup.haveAccountPost')}
</p>
<p class="prose-small"><a href="/">{$t('signup.backToFront')}</a></p>

<section class="section" style="text-align: center; margin-top: var(--space-5);">
  <LangSwitch />
</section>

<style>
  .agree {
    display: flex;
    align-items: flex-start;
    gap: 0.55rem;
    font-size: 0.9rem;
    line-height: 1.5;
  }
  .agree input[type='checkbox'] {
    margin-top: 0.2rem;
    flex: 0 0 auto;
  }
</style>
