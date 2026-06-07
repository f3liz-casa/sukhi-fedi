<script lang="ts">
  // ことばを選ぶ、ちいさなボタンの組。名前はその言語の文字で出す。
  import { t, locale, setLocale, LOCALES, LOCALE_NAMES } from '$lib/i18n';
</script>

<div class="lang-switch" role="group" aria-label={$t('lang.switch')}>
  {#each LOCALES as l (l)}
    <button
      type="button"
      class="chip"
      class:active={$locale === l}
      aria-pressed={$locale === l}
      onclick={() => setLocale(l)}
    >{LOCALE_NAMES[l]}</button>
  {/each}
</div>

<style>
  .lang-switch {
    display: inline-flex;
    gap: var(--space-2);
  }
  .lang-switch .chip.active {
    background: var(--fill-active);
  }
</style>
