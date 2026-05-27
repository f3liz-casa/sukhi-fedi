<script lang="ts">
  import '../styles/app.css';
  import UpdateBanner from '$lib/components/UpdateBanner.svelte';
</script>

<main class="wrap stack">
  <slot />
</main>

<UpdateBanner />
