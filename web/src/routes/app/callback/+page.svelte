<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { completeLogin } from '$lib/auth';

  let error: string | null = null;

  onMount(async () => {
    const params = new URLSearchParams(window.location.search);
    const code = params.get('code');
    const state = params.get('state');
    const err = params.get('error');

    if (err) {
      error = 'サーバから「' + err + '」と返ってきました。';
      return;
    }

    if (!code || !state) {
      error = 'urlに、足りないものがあるみたいです。';
      return;
    }

    try {
      await completeLogin(code, state);
      goto('/timeline');
    } catch (e) {
      error = e instanceof Error ? e.message : 'unknown';
    }
  });
</script>

{#if error}
  <section class="hero">
    <h1>うまく入れませんでした。</h1>
    <p class="tagline">{error}</p>
  </section>
  <p class="prose-small"><a href="/">トップにもどる</a></p>
{:else}
  <p class="loading">入っています…</p>
{/if}
