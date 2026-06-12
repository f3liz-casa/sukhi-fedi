<script lang="ts">
  import { onMount } from 'svelte';
  import {
    goToCheck,
    saveSignupDraft,
    loadSignupDraft,
    requestSignupEmailCode,
    confirmSignupEmailCode
  } from '$lib/auth';
  import { t, locale } from '$lib/i18n';
  import LangSwitch from '$lib/components/LangSwitch.svelte';

  // 加入は「メールボックスを開けられること」の証明から始まる。
  // コードを確認すると署名つきの email_proof が貰え、それを持って
  // /check へ進む。あいことばはレガシー・任意 ─ 折りたたみの中。
  let username = $state('');
  let password = $state('');
  let invite_code = $state('');
  let agreed = $state(false);
  let error = $state<string | null>(null);

  let email = $state('');
  let emailCode = $state('');
  let emailPhase = $state<'input' | 'sent' | 'proven'>('input');
  let emailProof = $state<string | null>(null);
  let emailBusy = $state(false);
  let restored = $state(false);

  // Send the consent links to the legal page in the current UI language.
  const termsHref = $derived($locale === 'ko' ? '/terms?lang=ko' : '/terms');
  const privacyHref = $derived($locale === 'ko' ? '/privacy?lang=ko' : '/privacy');

  // /check で失敗して戻ってきた人のために下書きを復元する。
  // password だけは(/check が clearSignupPassword で落とすので)
  // 復活しない。email_proof は残る ─ 20分のあいだは作り直し不要。
  onMount(() => {
    const d = loadSignupDraft();
    if (d) {
      restored = true;
      username = d.username ?? '';
      invite_code = d.invite_code ?? '';
      email = d.email ?? '';
      if (d.email_proof) {
        emailProof = d.email_proof;
        emailPhase = 'proven';
      }
    }
  });

  function explainEmail(e: unknown): string {
    const msg = e instanceof Error ? e.message : '';
    switch (msg) {
      case 'email':
        return $t('security.emailInvalid');
      case 'email_taken':
        return $t('security.emailTaken');
      case 'code':
        return $t('security.codeWrong');
      case 'expired':
        return $t('security.codeExpired');
      case 'rate_limited':
      case 'too_many_attempts':
        return $t('login.rateLimited');
      case 'send_failed':
        return $t('security.sendFailed');
      default:
        return $t('common.deliverFailed');
    }
  }

  // Anubis の cookie がフォーム滞在中に切れていたら、ページを読み
  // 直す ─ ページ自体が challenge されているので、PoW が再走して
  // cookie が戻り、入力した下書きは sessionStorage から復元される。
  function reloadIfAnubis(e: unknown): boolean {
    if (e instanceof Error && e.message === 'anubis') {
      saveSignupDraft({ username, invite_code, email });
      window.location.reload();
      return true;
    }
    return false;
  }

  async function sendEmailCode() {
    if (emailBusy) return;
    emailBusy = true;
    error = null;
    try {
      await requestSignupEmailCode(email);
      emailPhase = 'sent';
    } catch (e) {
      if (!reloadIfAnubis(e)) error = explainEmail(e);
    } finally {
      emailBusy = false;
    }
  }

  async function confirmEmail() {
    if (emailBusy) return;
    emailBusy = true;
    error = null;
    try {
      emailProof = await confirmSignupEmailCode(email, emailCode);
      emailPhase = 'proven';
    } catch (e) {
      if (!reloadIfAnubis(e)) error = explainEmail(e);
    } finally {
      emailBusy = false;
    }
  }

  function editEmail() {
    emailPhase = 'input';
    emailProof = null;
    emailCode = '';
  }

  function submit() {
    if (!emailProof) {
      error = $t('signup.emailProofNeeded');
      return;
    }
    error = null;
    saveSignupDraft({
      username,
      invite_code,
      email,
      email_proof: emailProof,
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
  <!-- ① メールの確認 ─ ここが正面玄関 -->
  {#if emailPhase === 'proven'}
    <div class="stack-tight">
      <span>{$t('signup.email')}</span>
      <p class="proven">
        <code>{email}</code>
        <span class="muted">{$t('signup.emailProven')}</span>
        <button type="button" class="chip" onclick={editEmail}>{$t('security.emailChange')}</button>
      </p>
    </div>
  {:else}
    <label class="stack-tight">
      <span>{$t('signup.email')}</span>
      <input
        type="email"
        bind:value={email}
        autocomplete="email"
        autocapitalize="none"
        spellcheck="false"
        disabled={emailPhase === 'sent'}
        required
      />
      <span class="help">{$t('signup.emailHelp')}</span>
    </label>

    {#if emailPhase === 'sent'}
      <label class="stack-tight">
        <span>{$t('login.code')}</span>
        <input
          type="text"
          bind:value={emailCode}
          inputmode="numeric"
          autocomplete="one-time-code"
          pattern="[0-9]{'{6}'}"
        />
      </label>
      <div class="row">
        <button type="button" disabled={emailBusy} onclick={() => void confirmEmail()}
          >{$t('security.confirm')}</button
        >
        <button type="button" class="chip" disabled={emailBusy} onclick={() => void sendEmailCode()}
          >{$t('login.sendAgain')}</button
        >
        <button type="button" class="chip" onclick={editEmail}>{$t('security.emailChange')}</button>
      </div>
    {:else}
      <button type="button" disabled={emailBusy || !email} onclick={() => void sendEmailCode()}
        >{$t('login.sendCode')}</button
      >
    {/if}
  {/if}

  <!-- ② なまえと招待コード -->
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

  <!-- ③ あいことば(レガシー・任意) ─ 折りたたみの中 -->
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

  <button type="submit" disabled={!agreed || emailPhase !== 'proven'}>{$t('signup.create')}</button>
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
  .proven {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex-wrap: wrap;
    margin: 0;
  }
  .row {
    display: flex;
    gap: var(--space-2);
    flex-wrap: wrap;
    align-items: center;
  }
  .legacy-pw summary {
    cursor: pointer;
    color: var(--color-text-muted);
    font-size: 0.9rem;
  }
</style>
