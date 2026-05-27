<script lang="ts">
  import type { Account, Relationship } from '$lib/api';
  import FollowButton from './FollowButton.svelte';
  import { phrase } from '$lib/phrase';

  export let account: Account;
  // 自分自身のときはボタンを出さない、外から null を渡す。
  export let relationship: Relationship | null = null;

  $: name = account.display_name || account.username;
</script>

<article class="account-row">
  <a class="account-row-link" href={`/@${account.acct}`}>
    {#if account.avatar}
      <img class="avatar" src={account.avatar} alt="" loading="lazy" />
    {:else}
      <span class="avatar" aria-hidden="true"></span>
    {/if}
    <span class="stack-tight">
      <span class="display-name">{@html phrase(name)}</span>
      <span class="muted">@{account.acct}</span>
    </span>
  </a>
  {#if relationship}
    <FollowButton accountId={account.id} {relationship} />
  {/if}
</article>
