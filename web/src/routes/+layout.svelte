<script lang="ts">
  import '../styles/app.css';
  import UpdateBanner from '$lib/components/UpdateBanner.svelte';
  import type { Snippet } from 'svelte';

  let { children }: { children?: Snippet } = $props();
</script>

<main class="wrap stack">
  {@render children?.()}
</main>

<UpdateBanner />
