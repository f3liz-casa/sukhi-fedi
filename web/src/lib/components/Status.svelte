<script lang="ts">
  import type { Status } from '$lib/api';

  export let status: Status;

  // Display name falls back to username when servers omit it (Misskey
  // sometimes does for fresh actors).
  $: name = status.account.display_name || status.account.username;
  $: avatar = status.account.avatar || null;
  $: ts = formatTime(status.created_at);

  function formatTime(iso: string): string {
    try {
      const d = new Date(iso);
      const now = Date.now();
      const diff = (now - d.getTime()) / 1000;
      if (diff < 60) return 'いま';
      if (diff < 3600) return Math.floor(diff / 60) + ' 分前';
      if (diff < 86_400) return Math.floor(diff / 3600) + ' 時間前';
      if (diff < 86_400 * 7) return Math.floor(diff / 86_400) + ' 日前';
      return d.toLocaleDateString('ja-JP');
    } catch {
      return iso;
    }
  }
</script>

<article class="status">
  {#if avatar}
    <img class="avatar" src={avatar} alt="" loading="lazy" />
  {:else}
    <span class="avatar" aria-hidden="true"></span>
  {/if}

  <div class="body">
    <header class="meta">
      <span class="display-name">{name}</span>
      <span>@{status.account.acct}</span>
      <span>·</span>
      <a href={status.url ?? '#'} rel="external noopener">{ts}</a>
    </header>

    {#if status.spoiler_text}
      <details>
        <summary>{status.spoiler_text}</summary>
        <div class="content">{@html status.content}</div>
      </details>
    {:else}
      <div class="content">{@html status.content}</div>
    {/if}

    {#if status.media_attachments.length > 0}
      <div class="media">
        {#each status.media_attachments as m (m.id)}
          {#if m.type === 'image'}
            <img src={m.preview_url || m.url} alt={m.description || ''} loading="lazy" />
          {/if}
        {/each}
      </div>
    {/if}
  </div>
</article>
