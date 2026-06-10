<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { getFavourites, type Status } from '$lib/api';
  import { isLoggedIn, clearToken } from '$lib/auth';
  import StatusCard from '$lib/components/Status.svelte';
  import { t } from '$lib/i18n';

  let items = $state<Status[]>([]);
  let nextMaxId = $state<string | null>(null);
  let loading = $state(false);
  let error = $state<string | null>(null);
  let initial = $state(true);

  onMount(() => {
    if (!isLoggedIn()) {
      goto('/');
      return;
    }
    void load(true);
  });

  async function load(reset: boolean) {
    if (loading) return;
    loading = true;
    error = null;

    if (reset) {
      items = [];
      nextMaxId = null;
    }

    try {
      const page = await getFavourites({ maxId: reset ? null : nextMaxId });
      items = reset ? page.items : [...items, ...page.items];
      nextMaxId = page.nextMaxId;
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'unknown';
      if (msg === 'unauthorized') {
        clearToken();
        goto('/');
        return;
      }
      error = $t('common.deliverFailedRetry');
    } finally {
      loading = false;
      initial = false;
    }
  }

  // お気に入りを外したら、その場でこの一覧から外す。
  function onUpdate(s: Status) {
    if (!s.favourited) items = items.filter((it) => it.id !== s.id);
  }
</script>

<header class="timeline page-head">
  <h1>{$t('favourites.title')}</h1>
</header>

<section class="timeline">
  {#if error}
    <p class="error">{error}</p>
  {:else if initial && loading}
    <p class="loading">{$t('common.loading')}</p>
  {:else if items.length === 0 && !loading}
    <p class="prose-small">{$t('favourites.empty')}</p>
  {/if}

  {#each items as s (s.id)}
    <StatusCard
      status={s}
      onupdate={onUpdate}
      ondelete={(d) => (items = items.filter((it) => it.id !== d.id))}
    />
  {/each}

  {#if !initial && loading}
    <p class="loading">{$t('common.loading')}</p>
  {/if}

  {#if nextMaxId && !loading}
    <button class="load-more" onclick={() => load(false)}>{$t('common.loadMore')}</button>
  {/if}
</section>
