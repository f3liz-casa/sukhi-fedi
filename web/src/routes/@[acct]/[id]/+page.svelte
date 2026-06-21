<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import { getStatus, getContext, type Status } from '$lib/api';
  import { clearToken } from '$lib/auth';
  import StatusCard from '$lib/components/Status.svelte';
  import Composer from '$lib/components/Composer.svelte';
  import { t } from '$lib/i18n';

  let status = $state<Status | null>(null);
  let ancestors = $state<Status[]>([]);
  let descendants = $state<Status[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);

  let replyTo = $state<Status | null>(null);
  let quoteOf = $state<Status | null>(null);
  let composerOpen = $state(false);

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
          ? $t('thread.noteNotFound')
          : $t('common.deliverFailed');
    } finally {
      loading = false;
    }
  }

  // どのノートにも返信できる。返信先の公開範囲は Composer が引き継ぐので、
  // DM への返信はそのまま direct のまま、同じスレッドに繋がる。
  function onReply(s: Status) {
    replyTo = s;
    quoteOf = null;
    composerOpen = true;
  }

  function onQuote(s: Status) {
    quoteOf = s;
    replyTo = null;
    composerOpen = true;
    if (typeof window !== 'undefined') window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function openReply() {
    if (status) onReply(status);
  }

  function onPosted(s: Status) {
    // 送れた返事はその場でスレッドの末尾に足す。
    descendants = [...descendants, s];
    composerOpen = false;
    replyTo = null;
    quoteOf = null;
  }

  function onCancel() {
    composerOpen = false;
    replyTo = null;
    quoteOf = null;
  }

  function onDelete(s: Status) {
    // 本体を消したらこのスレッドはもう開けないので、タイムラインへ戻る。
    if (status && s.id === status.id) {
      void goto('/timeline');
      return;
    }
    ancestors = ancestors.filter((it) => it.id !== s.id);
    descendants = descendants.filter((it) => it.id !== s.id);
  }
</script>

{#if error}
  <p class="error">{error}</p>
  <p><a class="chip" href="/timeline">{$t('common.backToTimeline')}</a></p>
{:else if loading}
  <p class="loading">{$t('common.loading')}</p>
{:else if status}
  <section class="timeline thread">
    {#each ancestors as s (s.id)}
      <StatusCard status={s} canReply onreply={onReply} onquote={onQuote} ondelete={onDelete} />
    {/each}

    <div class="focused">
      <StatusCard status={status} canReply onreply={onReply} onquote={onQuote} ondelete={onDelete} />
    </div>

    {#each descendants as s (s.id)}
      <StatusCard status={s} canReply onreply={onReply} onquote={onQuote} ondelete={onDelete} />
    {/each}
  </section>

  {#if composerOpen}
    <Composer {replyTo} {quoteOf} prefillMention onposted={onPosted} oncancel={onCancel} />
  {:else}
    <button class="chip reply-open" onclick={openReply}>{$t('thread.reply')}</button>
  {/if}
{/if}

<style>
  /* スレッドの中で、いま見ているノートだけ、そっと際立たせる。 */
  .focused {
    border-left: 3px solid var(--color-text);
  }
  .reply-open {
    margin-top: var(--space-3);
  }
</style>
