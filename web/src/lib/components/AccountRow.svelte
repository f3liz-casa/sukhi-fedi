<script lang="ts">
  import type { Account, Relationship } from '$lib/api';
  import FollowButton from './FollowButton.svelte';
  import { phrase } from '$lib/phrase';
  import { renderEmojis } from '$lib/emoji';

  let {
    account,
    // 自分自身のときはボタンを出さない、外から null を渡す。
    relationship = null
  }: {
    account: Account;
    relationship?: Relationship | null;
  } = $props();

  let name = $derived(account.display_name || account.username);
</script>

<article class="account-row">
  <a class="account-row-link" href={`/@${account.acct}`}>
    {#if account.avatar}
      <img class="avatar" src={account.avatar} alt="" loading="lazy" />
    {:else}
      <span class="avatar" aria-hidden="true"></span>
    {/if}
    <span class="stack-tight">
      <span class="display-name">{@html renderEmojis(phrase(name), account.emojis)}</span>
      <span class="muted">@{account.acct}</span>
    </span>
  </a>
  {#if relationship}
    <FollowButton accountId={account.id} {relationship} />
  {/if}
</article>
