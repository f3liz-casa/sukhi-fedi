<script lang="ts">
  // 軽量の絵文字ピッカー。Phase 2 では固定リストで始める。
  // custom emoji / 検索つきの本格版は Phase 4 で考える。
  let { onpick, onclose }: { onpick: (emoji: string) => void; onclose?: () => void } = $props();

  const QUICK = [
    '👍', '❤️', '😆', '🎉', '😮',
    '😢', '🤔', '🙏', '🔥', '✨',
    '🌸', '☕', '🍵', '🌱', '🐈',
    '🐾', '💡', '👀', '👏', '🥺',
    '😺', '😴', '🫶', '🍡'
  ];

  function pick(e: string) {
    onpick(e);
    onclose?.();
  }
</script>

<div class="reaction-picker" role="dialog" aria-label="リアクションを選ぶ">
  <div class="grid">
    {#each QUICK as e (e)}
      <button type="button" class="pick" onclick={() => pick(e)} aria-label={e}>{e}</button>
    {/each}
  </div>
</div>

<style>
  .reaction-picker {
    background: var(--bg, #fff);
    border: 1px solid var(--border, rgba(0, 0, 0, 0.12));
    border-radius: 0.5rem;
    padding: 0.5rem;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.12);
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(6, 1fr);
    gap: 0.125rem;
  }
  .pick {
    background: transparent;
    border: none;
    padding: 0.375rem;
    font-size: 1.25rem;
    cursor: pointer;
    border-radius: 0.25rem;
  }
  .pick:hover {
    background: var(--hover, rgba(127, 127, 127, 0.15));
  }
</style>
