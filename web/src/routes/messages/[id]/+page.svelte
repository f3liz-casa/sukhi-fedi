<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import {
    getConversations,
    getContext,
    markConversationRead,
    type Conversation,
    type Status
  } from '$lib/api';
  import { isLoggedIn, clearToken } from '$lib/auth';
  import { renderEmojis } from '$lib/emoji';
  import { phrase } from '$lib/phrase';
  import StatusCard from '$lib/components/Status.svelte';
  import Composer from '$lib/components/Composer.svelte';
  import { t } from '$lib/i18n';

  let convo = $state<Conversation | null>(null);
  let messages = $state<Status[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);

  let id = $derived($page.params.id ?? '');

  onMount(() => {
    if (!isLoggedIn()) {
      void goto('/');
      return;
    }
    void load();
  });

  async function load() {
    loading = true;
    error = null;
    try {
      // 会話そのものを引く API はないので、一覧から自分の行を見つける。
      // last_status を起点にスレッドの前後をつないで、ひと続きで出す。
      const list = await getConversations({});
      const c = list.items.find((x) => x.id === id) ?? null;
      convo = c;

      const seed = c?.last_status;
      if (seed) {
        const ctx = await getContext(seed.id);
        messages = [...ctx.ancestors, seed, ...ctx.descendants];
      } else {
        messages = [];
      }

      // 開いた時点でそっと既読に。印が同期できなくても表示は止めない。
      if (c?.unread) {
        try {
          await markConversationRead(c.id);
          convo = { ...c, unread: false };
        } catch {
          // 既読の同期失敗はそっとしておく。
        }
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      if (msg === 'unauthorized') {
        clearToken();
        void goto('/');
        return;
      }
      error = $t('common.deliverFailedRetry');
    } finally {
      loading = false;
    }
  }

  // 返信は、いまスレッドにいる相手みんなに宛てる。グループのまま返したい
  // ので、最後のメッセージの author 一人だけでなく、会話の参加者全員を
  // 宛先にする(でないと黙って一対一に縮んでしまう)。
  let lastStatus = $derived(messages.length > 0 ? messages[messages.length - 1] : null);
  let recipients = $derived((convo?.accounts ?? []).map((a) => a.acct));

  function withLabel(c: Conversation): string {
    const names = c.accounts.map((a) => a.display_name || a.username);
    if (names.length === 0) return $t('messages.self');
    return names.join($t('messages.nameSep'));
  }

  function onPosted(s: Status) {
    // 送れた返事は、その場でスレッドの末尾に足す。
    messages = [...messages, s];
  }
</script>

<header class="timeline page-head">
  <a class="chip" href="/messages">{$t('messages.back')}</a>
  {#if convo}
    <h1>{@html renderEmojis(phrase(withLabel(convo)), convo.accounts[0]?.emojis)}</h1>
  {/if}
</header>

<section class="timeline thread">
  {#if error}
    <p class="error">{error}</p>
  {:else if loading}
    <p class="loading">{$t('common.loading')}</p>
  {:else if messages.length === 0}
    <p class="prose-small">{$t('messages.threadEmpty')}</p>
  {:else}
    {#each messages as s (s.id)}
      <StatusCard status={s} />
    {/each}
  {/if}
</section>

{#if lastStatus && !loading && !error}
  <Composer
    replyTo={lastStatus}
    prefillRecipients={recipients}
    onposted={onPosted}
  />
{/if}
