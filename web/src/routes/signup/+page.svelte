<script lang="ts">
  import { onMount } from 'svelte';
  import {
    goToCheck,
    saveSignupDraft,
    loadSignupDraft
  } from '$lib/auth';

  let username = '';
  let password = '';
  let invite_code = '';
  let error: string | null = null;

  // /check で失敗して戻ってきた人のために下書きを復元するが、
  // password だけは(/check が clearSignupPassword で落としてあるので)
  // 復活しない。retry のときは合言葉だけもう一度打ってもらう。
  onMount(() => {
    const d = loadSignupDraft();
    if (d) {
      username = d.username ?? '';
      invite_code = d.invite_code ?? '';
      if (!d.password) {
        error = '合言葉だけ、もう一度入れてください。';
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
  <h1>はじめる</h1>
  <p class="tagline">招待コードと、なまえと、あいことばを、おしえてください。</p>
</section>

{#if error}
  <p class="error">{error}</p>
{/if}

<form class="form stack" on:submit|preventDefault={submit}>
  <label class="stack-tight">
    <span>ID</span>
    <input
      type="text"
      bind:value={username}
      autocomplete="username"
      pattern="[a-z0-9_]{'{1,30}'}"
      title="小文字英字、数字、アンダースコアだけ。30字まで。"
      required
    />
    <span class="help">小文字英字、数字、_（アンダースコア）。30字まで。例: <code>usagi_05</code></span>
  </label>

  <label class="stack-tight">
    <span>あいことば</span>
    <input
      type="password"
      bind:value={password}
      autocomplete="new-password"
      minlength="8"
      required
    />
    <span class="help">8字以上。</span>
  </label>

  <label class="stack-tight">
    <span>招待コード</span>
    <input type="text" bind:value={invite_code} autocomplete="off" required />
  </label>

  <button type="submit">作る</button>
</form>

<p class="prose-small">
  すでに住んでいる人は、<a href="/login" data-sveltekit-reload>こちらから入れます</a>。
</p>
