<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { getLists, createList, updateList, deleteList, type List } from '$lib/api';
  import { isLoggedIn, clearToken } from '$lib/auth';
  import { t } from '$lib/i18n';
  import { refreshCircles } from '$lib/circles';

  let lists = $state<List[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);
  let newTitle = $state('');
  // 既定 ON: ここで作るのは主に「ホームに出さない」サークル用途だから。
  let exclusive = $state(true);
  let creating = $state(false);

  onMount(() => {
    if (!isLoggedIn()) {
      goto('/');
      return;
    }
    void load();
  });

  async function load() {
    loading = true;
    error = null;
    try {
      lists = await getLists();
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      if (msg === 'unauthorized') {
        clearToken();
        goto('/');
        return;
      }
      error = $t('common.readFailed');
    } finally {
      loading = false;
    }
  }

  async function create() {
    const title = newTitle.trim();
    if (!title || creating) return;
    creating = true;
    try {
      const l = await createList(title, { exclusive });
      lists = [...lists, l];
      newTitle = '';
    } catch {
      // 失敗時はそのまま。
    } finally {
      creating = false;
    }
  }

  async function remove(l: List) {
    if (!confirm($t('lists.confirmDelete', { title: l.title }))) return;
    try {
      await deleteList(l.id);
      lists = lists.filter((x) => x.id !== l.id);
      void refreshCircles();
    } catch {
      // 失敗時はそのまま。
    }
  }

  // 既存リストの「ホームに出さない」を切替。成功で state を差し替え、失敗時は
  // 何もしない（checkbox は l.exclusive に描き戻る）。バッジ対象も変わるので
  // refreshCircles する。
  async function toggleExclusive(l: List, value: boolean) {
    try {
      const updated = await updateList(l.id, { exclusive: value });
      lists = lists.map((x) => (x.id === l.id ? updated : x));
      void refreshCircles();
    } catch {
      // 失敗時はそのまま。
    }
  }
</script>

<p class="back-row timeline"><a class="back-link" href="/timeline">← {$t('common.timeline')}</a></p>
<header class="timeline page-head">
  <h1>{$t('lists.title')}</h1>
</header>

<section class="timeline">
  <form
    class="form"
    onsubmit={(e) => {
      e.preventDefault();
      void create();
    }}
    style="margin-bottom: var(--space-4);"
  >
    <div style="display: flex; gap: var(--space-2);">
      <input
        type="text"
        bind:value={newTitle}
        placeholder={$t('lists.newPlaceholder')}
        maxlength="60"
        style="flex: 1;"
      />
      <button type="submit" disabled={creating || !newTitle.trim()}>{$t('lists.create')}</button>
    </div>
    <label style="display: flex; align-items: center; gap: var(--space-2); margin-top: var(--space-2);">
      <input type="checkbox" bind:checked={exclusive} />
      <span class="prose-small">{$t('lists.exclusiveLabel')}</span>
    </label>
  </form>

  {#if error}
    <p class="error">{error}</p>
  {:else if loading}
    <p class="loading">{$t('common.loading')}</p>
  {:else if lists.length === 0}
    <p class="prose-small">{$t('lists.empty')}</p>
  {:else}
    {#each lists as l (l.id)}
      <article class="list-row">
        <a class="list-link" href={`/lists/${l.id}`}>{l.title}</a>
        <label class="excl" title={$t('lists.exclusiveLabel')}>
          <input
            type="checkbox"
            checked={l.exclusive}
            onchange={(e) => toggleExclusive(l, e.currentTarget.checked)}
          />
          <span class="prose-small">{$t('lists.exclusiveShort')}</span>
        </label>
        <button type="button" class="chip" onclick={() => remove(l)}>{$t('lists.delete')}</button>
      </article>
    {/each}
  {/if}
</section>

<style>
  .list-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    padding: var(--space-3) 0;
    border-bottom: 1px solid var(--color-border);
  }
  .list-link {
    flex: 1;
    text-decoration: none;
    color: inherit;
    font-weight: 600;
  }
  .list-link:hover {
    text-decoration: underline;
  }
  .excl {
    display: flex;
    align-items: center;
    gap: var(--space-1);
    white-space: nowrap;
  }
</style>
