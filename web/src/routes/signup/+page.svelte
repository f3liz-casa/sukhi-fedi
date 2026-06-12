<script lang="ts">
  import { onMount } from 'svelte';
  import { goToCheck, saveSignupDraft, loadSignupDraft } from '$lib/auth';
  import { t, locale } from '$lib/i18n';
  import LangSwitch from '$lib/components/LangSwitch.svelte';

  // フォームは一枚: メール・なまえ・招待コード・(任意・レガシーの)
  // あいことば。6桁コードの送信と入力は /check ─ Anubis の通り道 ─
  // の上で行われるので、ここからメールが出ることは無い。
  let username = $state('');
  let password = $state('');
  let email = $state('');
  let invite_code = $state('');
  let agreed = $state(false);
  let error = $state<string | null>(null);
  let restored = $state(false);

  // Send the consent links to the legal page in the current UI language.
  const termsHref = $derived($locale === 'ko' ? '/terms?lang=ko' : '/terms');
  const privacyHref = $derived($locale === 'ko' ? '/privacy?lang=ko' : '/privacy');

  // /check で失敗して戻ってきた人のために下書きを復元する。
  // password だけは(/check が clearSignupPassword で落とすので)
  // 復活しない。email_proof が残っていれば /check はコードの段を
  // 飛ばすので、ここでは気にしなくていい。
  onMount(() => {
    const d = loadSignupDraft();
    if (d) {
      restored = true;
      username = d.username ?? '';
      invite_code = d.invite_code ?? '';
      email = d.email ?? '';
    }
  });

  function submit() {
    error = null;
    const d = loadSignupDraft();
    saveSignupDraft({
      username,
      invite_code,
      email,
      // 同じアドレスのまま戻ってきた人は、20分以内なら前の証明を
      // 使い回せる(コードの打ち直しが要らない)。変えたなら無効。
      ...(d?.email_proof && d.email === email ? { email_proof: d.email_proof } : {}),
      ...(password ? { password } : {})
    });
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
{#if restored}
  <p class="prose-small">{$t('signup.draftRestored')}</p>
{/if}

<form
  class="form stack"
  onsubmit={(e) => {
    e.preventDefault();
    submit();
  }}
>
  <label class="stack-tight">
    <span>{$t('signup.email')}</span>
    <input
      type="email"
      bind:value={email}
      autocomplete="email"
      autocapitalize="none"
      spellcheck="false"
      required
    />
    <span class="help">{$t('signup.emailHelp')}</span>
  </label>

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
    <span>{$t('signup.inviteCode')}</span>
    <input type="text" bind:value={invite_code} autocomplete="off" required />
  </label>

  <!-- あいことば(レガシー・任意) ─ 折りたたみの中 -->
  <details class="legacy-pw">
    <summary>{$t('signup.passwordLegacy')}</summary>
    <label class="stack-tight" style="margin-top: var(--space-2);">
      <span>{$t('signup.password')}</span>
      <input type="password" bind:value={password} autocomplete="new-password" minlength="8" />
      <span class="help">{$t('signup.passwordOptionalHelp')}</span>
    </label>
  </details>

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
  .legacy-pw summary {
    cursor: pointer;
    color: var(--color-text-muted);
    font-size: 0.9rem;
  }
</style>
