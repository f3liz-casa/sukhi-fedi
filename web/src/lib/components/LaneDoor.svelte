<script lang="ts">
  export let href: string;
  export let title: string;
  export let lane: 'use' | 'build' = 'use';
  export let description: string = '';
</script>

<a class="lane-door" data-lane={lane} {href}>
  <h3>{title}</h3>
  {#if description}<p>{description}</p>{/if}
</a>
