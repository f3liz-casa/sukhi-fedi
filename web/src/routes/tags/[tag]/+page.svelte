<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import { fetchTimeline, type Status } from '$lib/api';
  import { isLoggedIn, clearToken } from '$lib/auth';
  import StatusCard from '$lib/components/Status.svelte';
  import { t } from '$lib/i18n';

  // ルートパラメータ。本文中のハッシュタグ（rel="tag"）はここに飛んでくる。
  let tag = $derived(decodeURIComponent($page.params.tag ?? ''));

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
  });

  // タグが変わったら（/tags/A → /tags/B の遷移）頭から読み直す。
  $effect(() => {
    void tag;
    if (isLoggedIn()) void load(true);
  });

  async function load(reset: boolean) {
    if (loading || !tag) return;
    loading = true;
    error = null;

    if (reset) {
      items = [];
      nextMaxId = null;
      initial = true;
    }

    try {
      const p = await fetchTimeline('tag', { tag, maxId: reset ? null : nextMaxId });
      items = reset ? p.items : [...items, ...p.items];
      nextMaxId = p.items.length === 0 ? null : p.nextMaxId;
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
</script>

<header class="timeline page-head">
  <h1>#{tag}</h1>
</header>

<section class="timeline">
  {#if error}
    <p class="error">{error}</p>
  {:else if initial && loading}
    <p class="loading">{$t('common.loading')}</p>
  {:else if items.length === 0 && !loading}
    <p class="prose-small">{$t('timeline.emptyTag', { tag })}</p>
  {/if}

  {#each items as s (s.id)}
    <StatusCard
      status={s}
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
