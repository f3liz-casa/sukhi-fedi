<script lang="ts">
  // 軽量の絵文字ピッカー。Phase 2 では固定リストで始める。
  // custom emoji / 検索つきの本格版は Phase 4 で考える。
  import Twemoji from './Twemoji.svelte';
  import { t } from '$lib/i18n';

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

<div class="reaction-picker" role="dialog" aria-label={$t('reaction.pick')}>
  <div class="grid">
    {#each QUICK as e (e)}
      <button type="button" class="pick" onclick={() => pick(e)} aria-label={e}><Twemoji emoji={e} /></button>
    {/each}
  </div>
</div>

<style>
  .reaction-picker {
    background: var(--color-surface);
    border: 1px solid var(--color-border-strong);
    border-radius: 0.5rem;
    padding: 0.5rem;
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
    background: var(--fill-hover);
  }
</style>
