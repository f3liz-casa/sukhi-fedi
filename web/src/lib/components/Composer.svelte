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
  import {
    loadComposeDraft,
    saveComposeDraft,
    clearComposeDraft
  } from '$lib/compose-draft';
  import { goto } from '$app/navigation';
  import { t } from '$lib/i18n';

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

  // 書きかけの下書きは、トップの新規ノートだけ覚える。返信のときは
  // 覚えない(replyTo があるとここは null)。初回マウントで一度だけ
  // 拾う ─ untrack の中なので、あとのユーザ入力では読み直さない。
  const restored = untrack(() => (replyTo ? null : loadComposeDraft()));

  // 初期値だけ prop を見たい(あとはユーザが書き換える)ので untrack で
  // 拾う。これがないと state_referenced_locally の warning が出る。
  let text = $state(
    untrack(() =>
      restored?.text ?? (prefillMention && replyTo ? `@${replyTo.account.acct} ` : '')
    )
  );
  let spoiler = $state(untrack(() => restored?.spoiler ?? ''));
  let useSpoiler = $state(untrack(() => restored?.useSpoiler ?? false));
  let sensitive = $state(untrack(() => restored?.sensitive ?? false));
  let visibility = $state<Visibility>(
    untrack(() => restored?.visibility ?? replyTo?.visibility ?? 'public')
  );
  let media = $state<MediaAttachment[]>([]);
  let uploading = $state(false);
  let posting = $state(false);
  let error = $state<string | null>(null);
  let fileInput: HTMLInputElement | undefined = $state();

  let visLabels: Record<Visibility, string> = $derived({
    public: $t('compose.visPublic'),
    unlisted: $t('compose.visUnlisted'),
    private: $t('compose.visPrivate'),
    direct: $t('compose.visDirect')
  });

  let canPost = $derived(
    !posting &&
      !uploading &&
      (text.trim().length > 0 || media.length > 0)
  );

  // 復元したことを、一言だけそっと伝える。捨てるか、送ると消える。
  let showRestored = $state(!!restored);

  // 書きながら、すこし手が止まったら覚える。トップの新規ノート専用。
  // 中身が空っぽになったら、覚えていたものは消す(空の下書きは残さない)。
  $effect(() => {
    if (replyTo) return;
    const snapshot = { text, spoiler, useSpoiler, sensitive, visibility };
    const id = setTimeout(() => {
      if (snapshot.text.trim() === '' && snapshot.spoiler.trim() === '') {
        clearComposeDraft();
      } else {
        saveComposeDraft(snapshot);
      }
    }, 800);
    return () => clearTimeout(id);
  });

  // 「捨てる」。書いたものを空に戻して、覚えていた下書きも消す。
  function discard() {
    text = '';
    spoiler = '';
    useSpoiler = false;
    sensitive = false;
    showRestored = false;
    clearComposeDraft();
  }

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
      error = handleErr(e, $t('compose.uploadFailed'));
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
      // 送れた。フォームを空に戻して親に渡す。覚えていた下書きも消す。
      text = '';
      spoiler = '';
      useSpoiler = false;
      sensitive = false;
      media = [];
      showRestored = false;
      clearComposeDraft();
      onposted?.(s);
    } catch (e) {
      error = handleErr(e, $t('compose.postFailed'));
    } finally {
      posting = false;
    }
  }

  function handleErr(e: unknown, fallback: string): string {
    const msg = e instanceof Error ? e.message : '';
    if (msg === 'unauthorized') {
      clearToken();
      void goto('/');
      return $t('compose.reauth');
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
      <span>{$t('compose.replyTo', { acct: replyTo.account.acct })}</span>
      <button type="button" class="chip" onclick={() => oncancel?.()}>{$t('compose.cancel')}</button>
    </p>
  {:else if showRestored}
    <p class="composer-reply">
      <span>{$t('compose.draftRestored')}</span>
      <button type="button" class="chip" onclick={discard}>{$t('compose.discardDraft')}</button>
    </p>
  {/if}

  {#if useSpoiler}
    <label class="stack-tight">
      <span>{$t('compose.spoilerLabel')}</span>
      <input
        type="text"
        bind:value={spoiler}
        placeholder={$t('compose.spoilerPlaceholder')}
        maxlength="80"
      />
    </label>
  {/if}

  <label class="stack-tight">
    <span class="visually-hidden">{$t('compose.bodyLabel')}</span>
    <textarea
      bind:value={text}
      rows={replyTo ? 3 : 4}
      placeholder={replyTo ? $t('compose.placeholderReply') : $t('compose.placeholderNew')}
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
            {$t('compose.removeMedia')}
          </button>
        </li>
      {/each}
    </ul>
  {/if}

  <div class="composer-row">
    <label class="chip">
      {$t('compose.addImage')}
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
      <span>{$t('compose.fold')}</span>
    </label>

    <label class="stack-tight">
      <input type="checkbox" bind:checked={sensitive} />
      <span>{$t('compose.sensitive')}</span>
    </label>

    <label class="stack-tight">
      <span class="visually-hidden">{$t('compose.visLabel')}</span>
      <select bind:value={visibility}>
        {#each Object.entries(visLabels) as [v, label] (v)}
          <option value={v}>{label}</option>
        {/each}
      </select>
    </label>

    <button type="submit" class="btn px-6 py-2" disabled={!canPost}>
      {posting ? $t('common.sending') : uploading ? $t('compose.uploading') : $t('compose.submit')}
    </button>
  </div>

  {#if error}
    <p class="error">{error}</p>
  {/if}
</form>
