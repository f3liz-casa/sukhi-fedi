<script lang="ts">
  // 共通の「通り道」。Anubis がこの path だけを CHALLENGE するので、
  // ここに来た時点で PoW は通過済み。あとは intent に従って続きを
  // やるだけ。
  //
  //   /check?intent=login            → OAuth コードフローを始める
  //   /check?intent=signup           → sessionStorage の下書きで
  //                                    POST /api/v1/accounts
  //
  // どちらも失敗した場合は、その場で「もう一度試す」リンクを出す
  // ─ 下書き(signup の場合)は残っているので入力し直しは要らない。
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import {
    startLogin,
    signup,
    loadSignupDraft,
    clearSignupDraft,
    clearSignupPassword
  } from '$lib/auth';
  import { t, type TranslationKey } from '$lib/i18n';

  let phase = $state<'working' | 'error'>('working');
  let intent = $state<'login' | 'signup' | null>(null);
  let error = $state<string | null>(null);

  // API (api/lib/sukhi_api/capabilities/mastodon_accounts.ex) が
  // 実際に返すキーに揃える。新しいキーをサーバに足したら、ここも
  // 一緒に書く。
  // サーバが返すエラーコード → 辞書の鍵。文言じたいは $t で引くので、
  // 表示の瞬間の locale に従う。
  const ERROR_KEYS: Record<string, TranslationKey> = {
    invite_code_required: 'check.err.invite_code_required',
    invite_invalid: 'check.err.invite_invalid',
    invite_used: 'check.err.invite_used',
    invite_expired: 'check.err.invite_expired',
    password_too_short: 'check.err.password_too_short',
    validation_failed: 'check.err.validation_failed',
    client_credentials_required: 'check.err.client_credentials_required',
    token_mint_failed: 'check.err.token_mint_failed',
    gateway_not_connected: 'check.err.gateway_not_connected',
    gateway_rpc_failed: 'check.err.gateway_rpc_failed',
    internal_error: 'check.err.internal_error',
    no_draft: 'check.err.no_draft',
    password_missing: 'check.err.password_missing'
  };

  // changeset の details: {username: ["...", ...]} の field を言語へ。
  // 一個目だけ拾えば十分(複数あっても見せると目が散る)。
  const FIELD_KEYS: Record<string, TranslationKey> = {
    username: 'check.field.username',
    password: 'check.field.password',
    email: 'check.field.email',
    invite_code: 'check.field.invite_code'
  };

  function formatValidation(details: Record<string, string[]> | undefined): string | null {
    if (!details) return null;
    const first = Object.entries(details)[0];
    if (!first) return null;
    const [field, msgs] = first;
    const label = FIELD_KEYS[field] ? $t(FIELD_KEYS[field]) : field;
    const msg = msgs?.[0] ?? '';
    return `${label}${msg}`;
  }

  onMount(async () => {
    const params = new URLSearchParams(window.location.search);
    const i = params.get('intent');

    if (i !== 'login' && i !== 'signup') {
      error = $t('check.unknownIntent');
      phase = 'error';
      return;
    }

    intent = i;

    try {
      if (intent === 'login') {
        await startLogin();
        // startLogin() は window.location.assign で /oauth/authorize へ
        // 飛ばすので、ここから先のコードは実質的に実行されない。
      } else {
        const draft = loadSignupDraft();
        if (!draft) throw new Error('no_draft');
        if (!draft.password) throw new Error('password_missing');

        const payload = {
          username: draft.username,
          password: draft.password,
          invite_code: draft.invite_code,
          email: draft.email
        };

        // API call の直前に sessionStorage から password だけ消す。
        // 成功でも失敗でも、もう password はそこに無い。retry の
        // ときは合言葉だけ打ち直してもらう ─ docs: clearSignupPassword
        clearSignupPassword();

        await signup(payload);
        clearSignupDraft();
        await goto('/timeline');
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'unknown';
      const details = (e as Error & { details?: Record<string, string[]> })?.details;
      const fieldHint = msg === 'validation_failed' ? formatValidation(details) : null;
      error = fieldHint ?? (ERROR_KEYS[msg] ? $t(ERROR_KEYS[msg]) : null) ?? $t('check.failedGeneric');
      phase = 'error';
    }
  });

  function retry() {
    window.location.reload();
  }
</script>

{#if phase === 'working'}
  <section class="hero">
    <h1>
      {#if intent === 'signup'}
        {$t('check.creatingAccount')}
      {:else if intent === 'login'}
        {$t('check.guidingLogin')}
      {:else}
        {$t('check.pleaseWaitTitle')}
      {/if}
    </h1>
  </section>
  <p class="loading">{$t('check.pleaseWait')}</p>
{:else if phase === 'error'}
  <section class="hero">
    <h1>{$t('check.failedTitle')}</h1>
  </section>
  <p class="error">{error}</p>
  <div class="stack">
    <button class="lane-door" onclick={retry} style="max-width: 16rem;">
      <h3>{$t('check.retry')}</h3>
    </button>
    {#if intent === 'signup'}
      <p class="prose-small">
        {$t('check.signupDraftKeptPre')}<a href="/signup">{$t('check.signupDraftKeptLink')}</a>{$t('check.signupDraftKeptPost')}
      </p>
    {:else}
      <p class="prose-small"><a href="/">{$t('common.backToTop')}</a></p>
    {/if}
  </div>
{/if}
