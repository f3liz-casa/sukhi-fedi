<script lang="ts">
  // SvelteKit が `_app/version.json` を kit.version.pollInterval ごと
  // に取りに行く。サーバ側で新しいビルドが配られて version 文字列が
  // 変わると `$updated.current` が true になるので、その瞬間に静かに
  // 「リロードしますか?」を出す。
  //
  // 即時 reload で押し付けない理由:
  // - 入力中だったり読書中だったりすると失礼
  // - ユーザの「いま」を尊重する
  //
  // 出したあと、ユーザがリロードを選ばないまま放っておくと、
  // SvelteKit はリンクを踏んだ瞬間に invalidateAll してくれるので、
  // バナーを無視しても通常操作で必ず追いつく(壊れる前に)。
  import { updated } from '$app/stores';

  function reload() {
    window.location.reload();
  }

  function dismiss() {
    // 一度閉じても polling は続くので、本当に新しい版が来たら
    // 次の interval で再表示される。明示的に消したいときは
    // sessionStorage に印を残せばよい(今は不要)。
    show = false;
  }

  let show = false;
  $: if ($updated.current) show = true;
</script>

{#if show}
  <aside class="update-banner" role="status" aria-live="polite">
    <p>新しい版が、来ました。</p>
    <div class="actions">
      <button type="button" on:click={reload}>読み込みなおす</button>
      <button type="button" class="secondary" on:click={dismiss}>あとで</button>
    </div>
  </aside>
{/if}

<style>
  .update-banner {
    position: fixed;
    left: var(--space-4);
    right: var(--space-4);
    bottom: var(--space-4);
    max-width: 24rem;
    margin-inline: auto;
    padding: var(--space-3) var(--space-4);
    background: var(--color-surface);
    border: 1px solid var(--color-border-strong);
    border-radius: var(--radius);
    display: flex;
    gap: var(--space-4);
    align-items: center;
    justify-content: space-between;
    font-size: var(--text-sm);
    z-index: 50;
  }

  .update-banner p {
    margin: 0;
  }

  .actions {
    display: flex;
    gap: var(--space-2);
    flex-shrink: 0;
  }

  button {
    font: inherit;
    padding: var(--space-1) var(--space-3);
    background: var(--color-surface);
    color: var(--color-text);
    border: 1px solid var(--color-border-strong);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  button:hover {
    border-color: var(--color-text);
  }

  button.secondary {
    color: var(--color-text-muted);
    border-color: var(--color-border);
  }
</style>
