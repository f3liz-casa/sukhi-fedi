<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { completeLogin } from '$lib/auth';
  import { t } from '$lib/i18n';

  let error = $state<string | null>(null);

  onMount(async () => {
    const params = new URLSearchParams(window.location.search);
    const code = params.get('code');
    const state = params.get('state');
    const err = params.get('error');

    if (err) {
      error = $t('callback.serverError', { err });
      return;
    }

    if (!code || !state) {
      error = $t('callback.urlMissing');
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
    <h1>{$t('callback.failedTitle')}</h1>
    <p class="tagline">{error}</p>
  </section>
  <p class="prose-small"><a href="/">{$t('common.backToTop')}</a></p>
{:else}
  <p class="loading">{$t('callback.entering')}</p>
{/if}
