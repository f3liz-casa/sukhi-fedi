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
    clearSignupDraft
  } from '$lib/auth';

  let phase: 'working' | 'error' = 'working';
  let intent: 'login' | 'signup' | null = null;
  let error: string | null = null;

  // API (api/lib/sukhi_api/capabilities/mastodon_accounts.ex) が
  // 実際に返すキーに揃える。新しいキーをサーバに足したら、ここも
  // 一緒に書く。
  const errorText: Record<string, string> = {
    invite_code_required: '招待コードを入れてください。',
    invite_invalid: 'その招待コードは、見つかりませんでした。',
    invite_used: 'その招待コードは、もう使われています。',
    invite_expired: 'その招待コードは、もう古くなっています。',
    password_too_short: 'あいことばは、8 文字以上で。',
    validation_failed: '入れた中で、なにかひとつ、見直してみてください。',
    client_credentials_required: 'サーバとの最初の握手が、できていませんでした。',
    token_mint_failed: 'アカウントは作れたのに、入れる札が出ませんでした。',
    gateway_not_connected: 'サーバに、まだ届いていません。すこし待ってみて、もう一度。',
    gateway_rpc_failed: 'サーバに、まだ届いていません。すこし待ってみて、もう一度。',
    internal_error: 'サーバの中で、なにかが転びました。',
    no_draft: '下書きが見つかりませんでした。もう一度はじめからお願いします。'
  };

  // changeset の details: {username: ["...", ...]} を日本語に。
  // 一個目だけ拾えば十分(複数あっても見せると目が散る)。
  const fieldName: Record<string, string> = {
    username: 'ID',
    password: 'あいことば',
    email: 'メール',
    invite_code: '招待コード'
  };

  function formatValidation(details: Record<string, string[]> | undefined): string | null {
    if (!details) return null;
    const first = Object.entries(details)[0];
    if (!first) return null;
    const [field, msgs] = first;
    const label = fieldName[field] ?? field;
    const msg = msgs?.[0] ?? '';
    return `${label}${msg}`;
  }

  onMount(async () => {
    const params = new URLSearchParams(window.location.search);
    const i = params.get('intent');

    if (i !== 'login' && i !== 'signup') {
      error = 'なにをするか、分からなくなってしまいました。';
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

        await signup(draft);
        clearSignupDraft();
        await goto('/timeline');
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'unknown';
      const details = (e as Error & { details?: Record<string, string[]> })?.details;
      const fieldHint = msg === 'validation_failed' ? formatValidation(details) : null;
      error = fieldHint ?? errorText[msg] ?? 'うまく進めませんでした。もう一度ためしますか?';
      phase = 'error';
    }
  });

  function retry() {
    window.location.reload();
  }
</script>

<section class="hero">
  <h1>ちょっとだけ、確かめさせてください。</h1>
  <p class="tagline">
    {#if phase === 'working'}
      すぐ済みます。
    {:else}
      —
    {/if}
  </p>
</section>

{#if phase === 'working'}
  <p class="loading">確かめています…</p>
{:else if phase === 'error'}
  <p class="error">{error}</p>
  <div class="stack">
    <button class="lane-door" on:click={retry} style="max-width: 16rem;">
      <h3>もう一度</h3>
    </button>
    {#if intent === 'signup'}
      <p class="prose-small">
        入力した内容は、まだ残っています。<a href="/signup">フォームに戻る</a>こともできます。
      </p>
    {:else}
      <p class="prose-small"><a href="/">トップにもどる</a></p>
    {/if}
  </div>
{/if}
