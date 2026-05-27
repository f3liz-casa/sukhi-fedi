<script lang="ts">
  import {
    followAccount,
    unfollowAccount,
    type Relationship
  } from '$lib/api';
  import { clearToken, isLoggedIn } from '$lib/auth';
  import { goto } from '$app/navigation';

  let {
    accountId,
    // null = まだ取れていない / 自分自身 などで「ボタンを出さない」
    relationship,
    onchange
  }: {
    accountId: string;
    relationship: Relationship | null;
    onchange?: (r: Relationship) => void;
  } = $props();

  let pending = $state(false);
  let error = $state<string | null>(null);

  // `state` という名前は rune `$state` の解析と衝突するのでズラす。
  let currentState = $derived(
    relationship?.following
      ? 'following'
      : relationship?.requested
        ? 'requested'
        : 'idle'
  );

  let label = $derived(
    currentState === 'following'
      ? 'フォロー中'
      : currentState === 'requested'
        ? '承認まち'
        : 'フォロー'
  );

  async function toggle() {
    if (!isLoggedIn()) {
      void goto('/');
      return;
    }
    if (pending || !relationship) return;
    pending = true;
    error = null;
    try {
      const r =
        currentState === 'following' || currentState === 'requested'
          ? await unfollowAccount(accountId)
          : await followAccount(accountId);
      onchange?.(r);
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      if (msg === 'unauthorized') {
        clearToken();
        void goto('/');
        return;
      }
      error = 'うまく届きませんでした。';
    } finally {
      pending = false;
    }
  }
</script>

{#if relationship}
  <button
    type="button"
    class="follow-btn"
    data-state={currentState}
    onclick={toggle}
    disabled={pending}
  >
    {pending ? '…' : label}
  </button>
  {#if error}
    <span class="error" style="font-size: var(--text-sm);">{error}</span>
  {/if}
{/if}
