<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import {
    followAccount,
    unfollowAccount,
    type Relationship
  } from '$lib/api';
  import { clearToken, isLoggedIn } from '$lib/auth';
  import { goto } from '$app/navigation';

  export let accountId: string;
  // null = まだ取れていない / 自分自身 などで「ボタンを出さない」
  export let relationship: Relationship | null;

  const dispatch = createEventDispatcher<{ change: Relationship }>();

  let pending = false;
  let error: string | null = null;

  $: state = relationship?.following
    ? 'following'
    : relationship?.requested
      ? 'requested'
      : 'idle';

  $: label =
    state === 'following'
      ? 'フォロー中'
      : state === 'requested'
        ? '承認まち'
        : 'フォロー';

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
        state === 'following' || state === 'requested'
          ? await unfollowAccount(accountId)
          : await followAccount(accountId);
      relationship = r;
      dispatch('change', r);
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
    data-state={state}
    on:click={toggle}
    disabled={pending}
  >
    {pending ? '…' : label}
  </button>
  {#if error}
    <span class="error" style="font-size: var(--text-sm);">{error}</span>
  {/if}
{/if}
