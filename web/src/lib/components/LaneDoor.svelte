<script lang="ts">
  let {
    href,
    title,
    lane = 'use',
    description = ''
  }: {
    href: string;
    title: string;
    lane?: 'use' | 'build';
    description?: string;
  } = $props();
</script>

<a class="lane-door" data-lane={lane} {href}>
  <h3>{title}</h3>
  {#if description}<p>{description}</p>{/if}
</a>
