<script lang="ts">
  import '../styles/app.css';
  import AppNav from '$lib/components/AppNav.svelte';
  import EmailNudge from '$lib/components/EmailNudge.svelte';
  import UpdateBanner from '$lib/components/UpdateBanner.svelte';
  import type { Snippet } from 'svelte';

  let { children }: { children?: Snippet } = $props();
</script>

<AppNav />

<main class="wrap stack">
  {@render children?.()}
</main>

<EmailNudge />
<UpdateBanner />
