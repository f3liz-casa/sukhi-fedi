<script lang="ts">
  import { untrack } from 'svelte';
  import {
    postStatus,
    uploadMedia,
    type MediaAttachment,
    type Status,
    type Visibility
  } from '$lib/api';
  import { clearToken } from '$lib/auth';
  import { goto } from '$app/navigation';

  let {
    replyTo = null,
    // 返信のとき、返信先 acct をテキスト先頭に入れたい場合に使う
    // (Mastodon 互換クライアントは「@user@host 」を頭につけて出す慣習)
    prefillMention = false,
    onposted,
    oncancel
  }: {
    replyTo?: Status | null;
    prefillMention?: boolean;
    onposted?: (s: Status) => void;
    oncancel?: () => void;
  } = $props();

  // 初期値だけ prop を見たい(あとはユーザが書き換える)ので untrack で
  // 拾う。これがないと state_referenced_locally の warning が出る。
  let text = $state(
    untrack(() =>
      prefillMention && replyTo ? `@${replyTo.account.acct} ` : ''
    )
  );
  let spoiler = $state('');
  let useSpoiler = $state(false);
  let sensitive = $state(false);
  let visibility = $state<Visibility>(untrack(() => replyTo?.visibility ?? 'public'));
  let media = $state<MediaAttachment[]>([]);
  let uploading = $state(false);
  let posting = $state(false);
  let error = $state<string | null>(null);
  let fileInput: HTMLInputElement | undefined = $state();

  const visLabels: Record<Visibility, string> = {
    public: 'みんなに',
    unlisted: 'みんなに（タイムラインに載せず）',
    private: 'フォロワーだけに',
    direct: '指名した人だけに'
  };

  let canPost = $derived(
    !posting &&
      !uploading &&
      (text.trim().length > 0 || media.length > 0)
  );

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
      onposted?.(s);
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

<form
  class="composer"
  onsubmit={(e) => {
    e.preventDefault();
    void submit();
  }}
>
  {#if replyTo}
    <p class="composer-reply">
      <span>@{replyTo.account.acct} へ、返信</span>
      <button type="button" class="chip" onclick={() => oncancel?.()}>やめる</button>
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
          <button type="button" class="chip" onclick={() => removeMedia(m.id)}>
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
        onchange={onFiles}
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
        {#each Object.entries(visLabels) as [v, label] (v)}
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
