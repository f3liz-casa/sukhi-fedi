<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import {
    postStatus,
    uploadMedia,
    type MediaAttachment,
    type Status,
    type Visibility
  } from '$lib/api';
  import { clearToken } from '$lib/auth';
  import { goto } from '$app/navigation';

  export let replyTo: Status | null = null;
  // 返信のとき、返信先 acct をテキスト先頭に入れたい場合に使う
  // (Mastodon 互換クライアントは「@user@host 」を頭につけて出す慣習)
  export let prefillMention = false;

  const dispatch = createEventDispatcher<{ posted: Status; cancel: void }>();

  let text = prefillMention && replyTo ? `@${replyTo.account.acct} ` : '';
  let spoiler = '';
  let useSpoiler = false;
  let sensitive = false;
  let visibility: Visibility = replyTo?.visibility ?? 'public';
  let media: MediaAttachment[] = [];
  let uploading = false;
  let posting = false;
  let error: string | null = null;
  let fileInput: HTMLInputElement;

  const visLabels: Record<Visibility, string> = {
    public: 'みんなに',
    unlisted: 'みんなに（タイムラインに載せず）',
    private: 'フォロワーだけに',
    direct: '指名した人だけに'
  };

  $: canPost =
    !posting &&
    !uploading &&
    (text.trim().length > 0 || media.length > 0);

  async function onFiles(ev: Event) {
    const input = ev.currentTarget as HTMLInputElement;
    const files = input.files ? Array.from(input.files) : [];
    if (files.length === 0) return;
    uploading = true;
    error = null;
    try {
      for (const f of files) {
        const m = await uploadMedia(f);
        media = [...media, m];
      }
    } catch (e) {
      error = handleErr(e, '画像が、うまく上がりませんでした。');
    } finally {
      uploading = false;
      input.value = '';
    }
  }

  function removeMedia(id: string) {
    media = media.filter((m) => m.id !== id);
  }

  async function submit() {
    if (!canPost) return;
    posting = true;
    error = null;
    try {
      const s = await postStatus({
        status: text,
        spoiler_text: useSpoiler ? spoiler : undefined,
        sensitive: sensitive || (useSpoiler && !!spoiler) || undefined,
        visibility,
        in_reply_to_id: replyTo?.id ?? null,
        media_ids: media.map((m) => m.id)
      });
      // 送れた。フォームを空に戻して親に渡す。
      text = '';
      spoiler = '';
      useSpoiler = false;
      sensitive = false;
      media = [];
      dispatch('posted', s);
    } catch (e) {
      error = handleErr(e, 'うまく送れませんでした。もう一度、ためしますか?');
    } finally {
      posting = false;
    }
  }

  function handleErr(e: unknown, fallback: string): string {
    const msg = e instanceof Error ? e.message : '';
    if (msg === 'unauthorized') {
      clearToken();
      void goto('/');
      return 'もう一度、入りなおしてください。';
    }
    return fallback;
  }
</script>

<form class="composer" on:submit|preventDefault={submit}>
  {#if replyTo}
    <p class="composer-reply">
      <span>@{replyTo.account.acct} へ、返信</span>
      <button type="button" class="chip" on:click={() => dispatch('cancel')}>やめる</button>
    </p>
  {/if}

  {#if useSpoiler}
    <label class="stack-tight">
      <span>先に見せる一言（折りたたみの表）</span>
      <input
        type="text"
        bind:value={spoiler}
        placeholder="例: ねむい話"
        maxlength="80"
      />
    </label>
  {/if}

  <label class="stack-tight">
    <span class="visually-hidden">本文</span>
    <textarea
      bind:value={text}
      rows={replyTo ? 3 : 4}
      placeholder={replyTo ? '返事を書く…' : 'いま、思っていること…'}
    ></textarea>
  </label>

  {#if media.length > 0}
    <ul class="composer-media">
      {#each media as m (m.id)}
        <li>
          {#if m.preview_url || m.url}
            <img src={m.preview_url || m.url} alt={m.description ?? ''} />
          {/if}
          <button type="button" class="chip" on:click={() => removeMedia(m.id)}>
            はずす
          </button>
        </li>
      {/each}
    </ul>
  {/if}

  <div class="composer-row">
    <label class="chip">
      画像を足す
      <input
        bind:this={fileInput}
        type="file"
        accept="image/*"
        multiple
        on:change={onFiles}
        style="display: none;"
      />
    </label>

    <label class="stack-tight">
      <input type="checkbox" bind:checked={useSpoiler} />
      <span>折りたたむ</span>
    </label>

    <label class="stack-tight">
      <input type="checkbox" bind:checked={sensitive} />
      <span>見せ注意</span>
    </label>

    <label class="stack-tight">
      <span class="visually-hidden">公開の範囲</span>
      <select bind:value={visibility}>
        {#each Object.entries(visLabels) as [v, label]}
          <option value={v}>{label}</option>
        {/each}
      </select>
    </label>

    <button type="submit" disabled={!canPost}>
      {posting ? '送っています…' : uploading ? '上がっています…' : '送る'}
    </button>
  </div>

  {#if error}
    <p class="error">{error}</p>
  {/if}
</form>
