<script lang="ts">
  import { t } from '$lib/i18n';

  // タイムライン(home/public/tag/リスト)共通の表示フィルター。チェックを変えたら
  // onchange で親が頭から読み直す。hide_boosts は home でだけ意味があるので、
  // showHideBoosts で出し分ける(リストや public では出さない)。右寄せ。
  let {
    onlyMedia = $bindable(false),
    hideBoosts = $bindable(false),
    hideSensitive = $bindable(false),
    showHideBoosts = false,
    onchange
  }: {
    onlyMedia?: boolean;
    hideBoosts?: boolean;
    hideSensitive?: boolean;
    showHideBoosts?: boolean;
    onchange?: () => void;
  } = $props();

  let open = $state(false);
  let active = $derived(
    [onlyMedia, showHideBoosts && hideBoosts, hideSensitive].filter(Boolean).length
  );
</script>

<div class="filter-bar">
  <button
    type="button"
    class="chip"
    aria-expanded={open}
    aria-haspopup="menu"
    onclick={() => (open = !open)}
  >
    {$t('timeline.filter')}{active > 0 ? ` (${active})` : ''}
  </button>
  {#if open}
    <div class="filter-menu" role="menu">
      <label class="filter-row">
        <input type="checkbox" bind:checked={onlyMedia} onchange={() => onchange?.()} />
        <span>{$t('timeline.onlyMedia')}</span>
      </label>
      {#if showHideBoosts}
        <label class="filter-row">
          <input type="checkbox" bind:checked={hideBoosts} onchange={() => onchange?.()} />
          <span>{$t('timeline.hideBoosts')}</span>
        </label>
      {/if}
      <label class="filter-row">
        <input type="checkbox" bind:checked={hideSensitive} onchange={() => onchange?.()} />
        <span>{$t('timeline.hideSensitive')}</span>
      </label>
    </div>
  {/if}
</div>

<style>
  /* 右寄せ。メニューは右端そろえで画面外に出さない。 */
  .filter-bar {
    position: relative;
    display: flex;
    justify-content: flex-end;
    margin-bottom: var(--space-3);
  }
  .filter-menu {
    position: absolute;
    right: 0;
    z-index: 10;
    margin-top: 0.25rem;
    min-width: 14rem;
    max-width: calc(100vw - 2rem);
    padding: 0.25rem;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    background: var(--color-surface);
  }
  .filter-row {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.375rem 0.5rem;
    cursor: pointer;
  }
  .filter-row:hover {
    background: var(--fill-hover);
  }
</style>
