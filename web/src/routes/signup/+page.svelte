<script lang="ts">
  import { onMount } from 'svelte';
  import {
    goToCheck,
    saveSignupDraft,
    loadSignupDraft,
    clearSignupDraft
  } from '$lib/auth';

  let username = '';
  let password = '';
  let invite_code = '';
  let error: string | null = null;

  // /check で失敗して戻ってきた人のために、下書きを復元する。成功
  // していたら clearSignupDraft 済みなので何も入らない。
  onMount(() => {
    const d = loadSignupDraft();
    if (d) {
      username = d.username;
      password = d.password;
      invite_code = d.invite_code;
    }
  });

  function submit() {
    error = null;
    saveSignupDraft({ username, password, invite_code });
    goToCheck('signup');
  }

  function onLoginLink(e: MouseEvent) {
    e.preventDefault();
    clearSignupDraft();
    goToCheck('login');
  }
</script>

<section class="hero">
  <h1>はじめる</h1>
  <p class="tagline">招待コードと、なまえと、あいことばを、おしえてください。</p>
</section>

{#if error}
  <p class="error">{error}</p>
{/if}

<form class="form stack" on:submit|preventDefault={submit}>
  <label class="stack-tight">
    <span>なまえ</span>
    <input
      type="text"
      bind:value={username}
      autocomplete="username"
      pattern="[a-z0-9_]{'{1,30}'}"
      title="小文字英数字とアンダースコア、30字まで"
      required
    />
  </label>

  <label class="stack-tight">
    <span>あいことば（8字以上）</span>
    <input
      type="password"
      bind:value={password}
      autocomplete="new-password"
      minlength="8"
      required
    />
  </label>

  <label class="stack-tight">
    <span>招待コード</span>
    <input type="text" bind:value={invite_code} autocomplete="off" required />
  </label>

  <button type="submit">作る</button>
</form>

<p class="prose-small">
  すでに住んでいる人は、<a href="/login" on:click={onLoginLink}>こちらから入れます</a>。
</p>
