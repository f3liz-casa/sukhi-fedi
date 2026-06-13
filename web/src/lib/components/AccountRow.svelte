<script lang="ts">
  import type { Account, Relationship } from '$lib/api';
  import FollowButton from './FollowButton.svelte';
  import Avatar from './Avatar.svelte';
  import CircleBadge from './CircleBadge.svelte';
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
    <Avatar class="avatar" src={account.avatar} {name} />
    <span class="stack-tight">
      <span class="display-name">{@html renderEmojis(phrase(name), account.emojis)}<CircleBadge accountId={account.id} /></span>
      <span class="muted">@{account.acct}</span>
    </span>
  </a>
  {#if relationship}
    <FollowButton accountId={account.id} {relationship} />
  {/if}
</article>
