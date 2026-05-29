<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import { getStatus, getContext, type Status } from '$lib/api';
  import { clearToken } from '$lib/auth';
  import StatusCard from '$lib/components/Status.svelte';

  let status = $state<Status | null>(null);
  let ancestors = $state<Status[]>([]);
  let descendants = $state<Status[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);

  let id = $derived($page.params.id ?? '');

  onMount(() => {
    void load();
  });

  async function load() {
    loading = true;
    error = null;
    try {
      // スレッドの前後を一緒に出したいので、本体と文脈を並べて取る。
      status = await getStatus(id);
      const ctx = await getContext(id);
      ancestors = ctx.ancestors;
      descendants = ctx.descendants;
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      if (msg === 'unauthorized') {
        clearToken();
        void goto('/');
        return;
      }
      error =
        msg === 'not_found'
          ? 'そのノートは、見つかりませんでした。'
          : 'うまく届きませんでした。';
    } finally {
      loading = false;
    }
  }
</script>

{#if error}
  <p class="error">{error}</p>
  <p><a class="chip" href="/timeline">タイムラインへ戻る</a></p>
{:else if loading}
  <p class="loading">読んでいます…</p>
{:else if status}
  <section class="timeline thread">
    {#each ancestors as s (s.id)}
      <StatusCard status={s} />
    {/each}

    <div class="focused">
      <StatusCard status={status} />
    </div>

    {#each descendants as s (s.id)}
      <StatusCard status={s} />
    {/each}
  </section>
{/if}

<style>
  /* スレッドの中で、いま見ているノートだけ、そっと際立たせる。 */
  .focused {
    border-left: 3px solid var(--accent, #6366f1);
  }
</style>
