<script lang="ts">
  // ログインと安全: メールアドレスの確認、アプリ 2FA(TOTP)、パスキー。
  // ぜんぶ session cookie 専用の管理面(auth.ts のコメント参照)。
  // cookie が無い/切れているときは manageable: false が返るので、
  // フォームを出さずに「入りなおしてください」を出す。
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import {
    isLoggedIn,
    fetchAuthState,
    requestEmailCode,
    confirmEmailCode,
    totpSetup,
    totpEnable,
    totpDisable,
    registerPasskey,
    deletePasskey,
    type AuthState
  } from '$lib/auth';
  import { passkeySupported } from '$lib/webauthn';
  import { t } from '$lib/i18n';
  import { renderSVG } from 'uqr';

  let auth = $state<AuthState | null>(null);
  let loading = $state(true);
  let error = $state<string | null>(null);
  let canPasskey = $state(false);

  onMount(() => {
    if (!isLoggedIn()) {
      void goto('/');
      return;
    }
    canPasskey = passkeySupported();
    void load();
  });

  async function load() {
    loading = true;
    error = null;
    try {
      auth = await fetchAuthState();
      if (!auth) {
        void goto('/');
        return;
      }
    } catch {
      error = $t('common.readFailed');
    } finally {
      loading = false;
    }
  }

  // 共通のエラー → ことば。鍵が無いものは「うまくいきませんでした」。
  function explain(e: unknown): string {
    const msg = e instanceof Error ? e.message : '';
    switch (msg) {
      case 'password':
        return $t('security.wrongPassword');
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
      case 'already_registered':
        return $t('security.passkeyDup');
      default:
        return $t('common.deliverFailed');
    }
  }

  // ── メール ──────────────────────────────────────────────────────────
  let emailInput = $state('');
  let emailPassword = $state('');
  let emailCodeSent = $state(false);
  let emailCode = $state('');
  let emailBusy = $state(false);
  let emailError = $state<string | null>(null);
  let emailEditing = $state(false);

  function startEmailEdit() {
    emailInput = auth?.email ?? '';
    emailPassword = '';
    emailCode = '';
    emailCodeSent = false;
    emailError = null;
    emailEditing = true;
  }

  async function sendEmail() {
    if (emailBusy) return;
    emailBusy = true;
    emailError = null;
    try {
      await requestEmailCode(emailInput, auth?.email_verified ? emailPassword : undefined);
      emailCodeSent = true;
    } catch (e) {
      emailError = explain(e);
    } finally {
      emailBusy = false;
    }
  }

  async function confirmEmail() {
    if (emailBusy) return;
    emailBusy = true;
    emailError = null;
    try {
      await confirmEmailCode(emailCode);
      emailEditing = false;
      await load();
    } catch (e) {
      emailError = explain(e);
    } finally {
      emailBusy = false;
    }
  }

  // ── TOTP ────────────────────────────────────────────────────────────
  let totp = $state<{ secret: string; otpauth: string } | null>(null);
  let totpQr = $derived(totp ? renderSVG(totp.otpauth) : null);
  let totpCode = $state('');
  let totpPassword = $state('');
  let totpBusy = $state(false);
  let totpError = $state<string | null>(null);

  async function startTotp() {
    if (totpBusy) return;
    totpBusy = true;
    totpError = null;
    try {
      totp = await totpSetup();
      totpCode = '';
    } catch (e) {
      totpError = explain(e);
    } finally {
      totpBusy = false;
    }
  }

  async function enableTotp() {
    if (totpBusy) return;
    totpBusy = true;
    totpError = null;
    try {
      await totpEnable(totpCode);
      totp = null;
      await load();
    } catch (e) {
      totpError = explain(e);
    } finally {
      totpBusy = false;
    }
  }

  async function disableTotp() {
    if (totpBusy) return;
    totpBusy = true;
    totpError = null;
    try {
      await totpDisable(totpPassword);
      totpPassword = '';
      await load();
    } catch (e) {
      totpError = explain(e);
    } finally {
      totpBusy = false;
    }
  }

  // ── パスキー ────────────────────────────────────────────────────────
  let passkeyNickname = $state('');
  let passkeyBusy = $state(false);
  let passkeyError = $state<string | null>(null);
  // 削除はうっかりが怖いので、行ごとにパスワード欄を開く。
  let deletingId = $state<number | null>(null);
  let deletePassword = $state('');

  async function addPasskey() {
    if (passkeyBusy) return;
    passkeyBusy = true;
    passkeyError = null;
    try {
      await registerPasskey(passkeyNickname);
      passkeyNickname = '';
      await load();
    } catch (e) {
      if (e instanceof DOMException && e.name === 'NotAllowedError') {
        // 自分でやめたときは、何も言わない。
      } else {
        passkeyError = explain(e);
      }
    } finally {
      passkeyBusy = false;
    }
  }

  async function removePasskey(id: number) {
    if (passkeyBusy) return;
    passkeyBusy = true;
    passkeyError = null;
    try {
      await deletePasskey(id, deletePassword);
      deletingId = null;
      deletePassword = '';
      await load();
    } catch (e) {
      passkeyError = explain(e);
    } finally {
      passkeyBusy = false;
    }
  }

  function fmtDate(iso: string | null): string {
    if (!iso) return '—';
    return iso.slice(0, 10);
  }
</script>

<header class="timeline page-head">
  <h1>{$t('security.title')}</h1>
</header>

{#if loading}
  <p class="loading">{$t('common.loading')}</p>
{:else if error}
  <p class="error">{error}</p>
{:else if auth && !auth.manageable}
  <section class="timeline" style="margin-block: var(--space-4);">
    <p>{$t('security.needRelogin')}</p>
    <p class="prose-small"><a class="chip" href="/login">{$t('security.reloginLink')}</a></p>
  </section>
{:else if auth}
  <!-- メール -->
  <section class="timeline sec">
    <h2>{$t('security.emailTitle')}</h2>
    {#if auth.email}
      <p>
        <code>{auth.email}</code>
        <span class="muted">
          {auth.email_verified ? $t('security.emailVerified') : $t('security.emailUnverified')}
        </span>
      </p>
    {:else}
      <p class="muted">{$t('security.emailNone')}</p>
    {/if}

    {#if !emailEditing}
      <p>
        <button type="button" class="chip" onclick={startEmailEdit}>
          {auth.email
            ? auth.email_verified
              ? $t('security.emailChange')
              : $t('security.emailVerify')
            : $t('security.emailSet')}
        </button>
      </p>
    {:else}
      <form
        class="form stack"
        onsubmit={(e) => {
          e.preventDefault();
          void (emailCodeSent ? confirmEmail() : sendEmail());
        }}
      >
        <label class="stack-tight">
          <span>{$t('security.emailTitle')}</span>
          <input type="email" bind:value={emailInput} autocomplete="email" required />
        </label>

        {#if auth.email_verified && !emailCodeSent}
          <label class="stack-tight">
            <span>{$t('security.passwordToConfirm')}</span>
            <input type="password" bind:value={emailPassword} autocomplete="current-password" required />
            <span class="help">{$t('security.passwordChangeHelp')}</span>
          </label>
        {/if}

        {#if emailCodeSent}
          <p class="prose-small">{$t('security.codeSent')}</p>
          <label class="stack-tight">
            <span>{$t('login.code')}</span>
            <input
              type="text"
              bind:value={emailCode}
              inputmode="numeric"
              autocomplete="one-time-code"
              pattern="[0-9]{'{6}'}"
              required
            />
          </label>
          <button type="submit" disabled={emailBusy}>{$t('security.confirm')}</button>
          <button type="button" class="chip" disabled={emailBusy} onclick={() => void sendEmail()}
            >{$t('login.sendAgain')}</button
          >
        {:else}
          <button type="submit" disabled={emailBusy}>{$t('login.sendCode')}</button>
        {/if}

        {#if emailError}
          <p class="error">{emailError}</p>
        {/if}
      </form>
    {/if}
  </section>

  <!-- アプリ 2FA -->
  <section class="timeline sec">
    <h2>{$t('security.totpTitle')}</h2>

    {#if auth.totp_enabled}
      <p class="muted">{$t('security.totpOn')}</p>
      <form
        class="form stack"
        onsubmit={(e) => {
          e.preventDefault();
          void disableTotp();
        }}
      >
        <label class="stack-tight">
          <span>{$t('security.passwordToConfirm')}</span>
          <input type="password" bind:value={totpPassword} autocomplete="current-password" required />
        </label>
        <button type="submit" disabled={totpBusy}>{$t('security.totpDisable')}</button>
      </form>
    {:else if totp}
      <p class="prose-small">{$t('security.totpScan')}</p>
      {#if totpQr}
        <div class="qr">{@html totpQr}</div>
      {/if}
      <p class="prose-small">
        {$t('security.totpSecret')}: <code>{totp.secret}</code>
      </p>
      <form
        class="form stack"
        onsubmit={(e) => {
          e.preventDefault();
          void enableTotp();
        }}
      >
        <label class="stack-tight">
          <span>{$t('security.totpConfirmHelp')}</span>
          <input
            type="text"
            bind:value={totpCode}
            inputmode="numeric"
            autocomplete="one-time-code"
            pattern="[0-9]{'{6}'}"
            required
          />
        </label>
        <button type="submit" disabled={totpBusy}>{$t('security.totpEnable')}</button>
      </form>
    {:else}
      <p class="muted">{$t('security.totpOff')}</p>
      <p>
        <button type="button" class="chip" disabled={totpBusy} onclick={() => void startTotp()}
          >{$t('security.totpStart')}</button
        >
      </p>
    {/if}

    {#if totpError}
      <p class="error">{totpError}</p>
    {/if}
  </section>

  <!-- パスキー -->
  <section class="timeline sec">
    <h2>{$t('security.passkeysTitle')}</h2>

    {#if auth.passkeys.length === 0}
      <p class="muted">{$t('security.passkeysNone')}</p>
    {:else}
      <ul class="passkeys">
        {#each auth.passkeys as pk (pk.id)}
          <li>
            <span>{pk.nickname ?? $t('security.passkeyUnnamed')}</span>
            <span class="muted">
              {$t('security.lastUsed')}: {fmtDate(pk.last_used_at)}
            </span>
            {#if deletingId === pk.id}
              <form
                class="form stack-tight inline-delete"
                onsubmit={(e) => {
                  e.preventDefault();
                  void removePasskey(pk.id);
                }}
              >
                <input
                  type="password"
                  bind:value={deletePassword}
                  placeholder={$t('security.passwordToConfirm')}
                  autocomplete="current-password"
                  required
                />
                <button type="submit" disabled={passkeyBusy}>{$t('security.passkeyDelete')}</button>
                <button
                  type="button"
                  class="chip"
                  onclick={() => {
                    deletingId = null;
                    deletePassword = '';
                  }}>{$t('security.cancel')}</button
                >
              </form>
            {:else}
              <button
                type="button"
                class="chip"
                onclick={() => {
                  deletingId = pk.id;
                  deletePassword = '';
                }}>{$t('security.passkeyDelete')}</button
              >
            {/if}
          </li>
        {/each}
      </ul>
    {/if}

    {#if canPasskey}
      <form
        class="form stack"
        onsubmit={(e) => {
          e.preventDefault();
          void addPasskey();
        }}
      >
        <label class="stack-tight">
          <span>{$t('security.passkeyNickname')}</span>
          <input type="text" bind:value={passkeyNickname} maxlength="50" />
        </label>
        <button type="submit" disabled={passkeyBusy}>{$t('security.passkeyAdd')}</button>
      </form>
    {:else}
      <p class="prose-small">{$t('security.passkeyUnsupported')}</p>
    {/if}

    {#if passkeyError}
      <p class="error">{passkeyError}</p>
    {/if}
  </section>

  <p class="prose-small" style="margin-top: var(--space-4);">
    <a href="/settings">{$t('security.backToSettings')}</a>
  </p>
{/if}

<style>
  .sec {
    margin-block: var(--space-5);
  }
  .sec h2 {
    font-size: var(--text-base);
    margin-bottom: var(--space-2);
  }
  .qr {
    max-width: 12rem;
    margin-block: var(--space-3);
  }
  .qr :global(svg) {
    width: 100%;
    height: auto;
    display: block;
  }
  .passkeys {
    list-style: none;
    padding: 0;
    margin: 0 0 var(--space-3);
  }
  .passkeys li {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--space-3);
    padding-block: var(--space-2);
    border-bottom: 1px solid var(--color-border);
  }
  .inline-delete {
    display: flex;
    gap: var(--space-2);
    align-items: center;
  }
</style>
