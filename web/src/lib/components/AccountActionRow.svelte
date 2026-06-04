<script lang="ts">
  import type { Account } from '$lib/api';
  import { phrase } from '$lib/phrase';
  import { renderEmojis } from '$lib/emoji';

  // アバター＋名前＋ひとつの操作ボタンの行。解除・外す・削除など、相手の
  // アカウントに対して一手だけ用意したい一覧（ブロック/ミュート管理、リスト
  // メンバー…）で使い回す。ボタンの文言と押したときの動作だけ外から渡す。
  let {
    account,
    actionLabel,
    onaction
  }: {
    account: Account;
    actionLabel: string;
    onaction: (a: Account) => void;
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
  <button type="button" class="chip" onclick={() => onaction(account)}>{actionLabel}</button>
</article>
