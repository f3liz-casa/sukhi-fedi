<script lang="ts">
  import { onMount } from 'svelte';
  import { isLoggedIn } from '$lib/auth';
  import { goto } from '$app/navigation';
  import LaneDoor from '$lib/components/LaneDoor.svelte';
  import LangSwitch from '$lib/components/LangSwitch.svelte';
  import { t } from '$lib/i18n';

  onMount(() => {
    if (isLoggedIn()) {
      goto('/timeline');
    }
  });

  // 「入る」は SPA の /login へ。資格情報を POST してセッションが立つと、
  // /login ページが /check?intent=login へ送り、そこで初めて Anubis の
  // PoW が走る ─ ユーザが何もしないうちに確認を要求しない作り。
</script>

<section class="hero">
  <h1>{$t('landing.heroTitle')}</h1>
  <p class="tagline">
    {@html $t('landing.tagline')}
  </p>
</section>

<section class="section">
  <div class="doors">
    <LaneDoor
      href="/signup"
      lane="use"
      title={$t('landing.startTitle')}
      description={$t('landing.startDesc')}
    />
    <a class="lane-door" data-lane="build" href="/login">
      <h3>{$t('landing.enterTitle')}</h3>
      <p>{$t('landing.enterDesc')}</p>
    </a>
  </div>
</section>

<section class="section">
  <p class="prose-small">
    {$t('landing.about')}
  </p>
</section>

<section class="section" style="text-align: center;">
  <LangSwitch />
</section>

<style>
  /* 行をならす(一文目向け)。二文目の末尾は <span class="nobr"> でひと固まりに
     して、「つながっています。」だけが取り残されないよう、折り返しを手前に
     寄せる。nobr は {@html} で注入されるので :global で当てる。 */
  .tagline {
    text-wrap: balance;
  }
  .tagline :global(.nobr) {
    white-space: nowrap;
  }
</style>

