<script lang="ts">
  import type { Status, Reaction, Poll } from '$lib/api';
  import * as api from '$lib/api';
  import Self from './Status.svelte';
  import ReactionPicker from './ReactionPicker.svelte';
  import { renderEmojis } from '$lib/emoji';
  import { phrase } from '$lib/phrase';

  let {
    status,
    // 返信ボタンを出すか。タイムラインでは true、プロフィール一覧では false
    // など、置き場ごとに切り替えたい。
    canReply = false,
    onreply,
    onupdate,
    ondelete
  }: {
    status: Status;
    canReply?: boolean;
    onreply?: (s: Status) => void;
    onupdate?: (s: Status) => void;
    // 自分のノートを削除したとき。置き場ごとに一覧から外したい。
    ondelete?: (s: Status) => void;
  } = $props();

  // Display name falls back to username when servers omit it (Misskey
  // sometimes does for fresh actors).
  let name = $derived(status.account.display_name || status.account.username);
  let avatar = $derived(status.account.avatar || null);
  let ts = $derived(formatTime(status.created_at));

  // ローカル state は楽観更新用。prop が差し替わったら sync する。
  let reactions = $state<Reaction[]>([]);
  let favourited = $state(false);
  let favCount = $state(0);
  let reblogged = $state(false);
  let reblogCount = $state(0);
  let bookmarked = $state(false);
  let pinned = $state(false);
  let pickerOpen = $state(false);
  // 自分のノートか（ピン留め・削除を出すか）。current id は memoise 済みなので
  // 一覧に何枚あっても verify_credentials は一度きり。loggedIn は通報を出すか。
  let mine = $state(false);
  let loggedIn = $state(false);
  let deleting = $state(false);
  // ⋯ メニュー。低頻度・破壊的な操作（ピン留め・通報・削除）をしまっておく。
  let menuOpen = $state(false);
  let reported = $state(false);

  $effect(() => {
    reactions = status.reactions ?? [];
    favourited = !!status.favourited;
    favCount = status.favourites_count ?? 0;
    reblogged = !!status.reblogged;
    reblogCount = status.reblogs_count ?? 0;
    bookmarked = !!status.bookmarked;
    pinned = !!status.pinned;
  });

  $effect(() => {
    const authorId = status.account.id;
    api.currentAccountId().then((id) => {
      loggedIn = !!id;
      mine = !!id && id === authorId;
    });
  });

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

  async function toggleReaction(emoji: string) {
    const snapshot = reactions;
    const idx = reactions.findIndex((r) => r.name === emoji);

    if (idx >= 0 && reactions[idx].me) {
      const next = { ...reactions[idx], me: false, count: reactions[idx].count - 1 };
      reactions =
        next.count <= 0
          ? reactions.filter((_, i) => i !== idx)
          : reactions.map((x, i) => (i === idx ? next : x));
      try {
        const s = await api.unreact(status.id, emoji);
        onupdate?.(s);
      } catch {
        reactions = snapshot;
      }
    } else if (idx >= 0) {
      const next = { ...reactions[idx], me: true, count: reactions[idx].count + 1 };
      reactions = reactions.map((x, i) => (i === idx ? next : x));
      try {
        const s = await api.react(status.id, emoji);
        onupdate?.(s);
      } catch {
        reactions = snapshot;
      }
    } else {
      reactions = [...reactions, { name: emoji, count: 1, me: true }];
      try {
        const s = await api.react(status.id, emoji);
        onupdate?.(s);
      } catch {
        reactions = snapshot;
      }
    }
  }

  function pickFromPicker(emoji: string) {
    pickerOpen = false;
    toggleReaction(emoji);
  }

  async function remove() {
    if (deleting) return;
    if (!confirm('このノートを削除しますか？ この操作は取り消せません。')) return;
    deleting = true;
    try {
      await api.deleteStatus(status.id);
      // 成功したら一覧から外す（このカードは外れて消える）。
      ondelete?.(status);
    } catch {
      // 失敗したら押せる状態に戻す。federation の Delete は非同期なので
      // ここでの成功はローカル削除＝即ビューから消える、で十分。
      deleting = false;
    }
  }

  async function toggleFavourite() {
    const wasFav = favourited;
    const before = favCount;
    favourited = !wasFav;
    favCount = wasFav ? Math.max(0, before - 1) : before + 1;
    try {
      const s = wasFav ? await api.unfavourite(status.id) : await api.favourite(status.id);
      onupdate?.(s);
    } catch {
      favourited = wasFav;
      favCount = before;
    }
  }

  async function toggleReblog() {
    const was = reblogged;
    const before = reblogCount;
    reblogged = !was;
    reblogCount = was ? Math.max(0, before - 1) : before + 1;
    try {
      const s = was ? await api.unreblog(status.id) : await api.reblog(status.id);
      onupdate?.(s);
    } catch {
      reblogged = was;
      reblogCount = before;
    }
  }

  async function toggleBookmark() {
    const was = bookmarked;
    bookmarked = !was;
    try {
      const s = was ? await api.unbookmark(status.id) : await api.bookmark(status.id);
      onupdate?.(s);
    } catch {
      bookmarked = was;
    }
  }

  // 自分のノートをプロフィール先頭に固定する。サーバが ownership を強制する。
  async function togglePin() {
    menuOpen = false;
    const was = pinned;
    pinned = !was;
    try {
      const s = was ? await api.unpinStatus(status.id) : await api.pinStatus(status.id);
      onupdate?.(s);
    } catch {
      pinned = was;
    }
  }

  // 通報。理由は任意（プロンプトをキャンセルしたら何もしない）。送れたら
  // メニューを「通報しました」に変えて二度押しを防ぐ。
  async function doReport() {
    const comment = prompt('通報の理由があれば書いてください（任意）');
    if (comment === null) return;
    menuOpen = false;
    try {
      await api.reportAccount(status.account.id, {
        statusIds: [status.id],
        comment: comment || undefined
      });
      reported = true;
    } catch {
      // 失敗時は黙って閉じる。開き直せば押し直せる。
    }
  }

  // ── poll ──────────────────────────────────────────────────────────
  // 投票は楽観更新せずサーバの集計をそのまま映す。投票後 / 締切後 / 既に
  // 投票済みは結果表示、それ以外は選択 UI。single choice は radio、
  // multiple は checkbox。
  let poll = $state<Poll | null>(null);
  let pollChoices = $state<number[]>([]);
  let pollVoting = $state(false);

  $effect(() => {
    poll = status.poll ?? null;
    pollChoices = [];
  });

  let pollTotal = $derived(poll ? Math.max(1, poll.votes_count) : 1);
  let pollClosed = $derived(!!poll && (poll.expired || !!poll.voted));

  function toggleChoice(idx: number) {
    if (!poll) return;
    if (poll.multiple) {
      pollChoices = pollChoices.includes(idx)
        ? pollChoices.filter((i) => i !== idx)
        : [...pollChoices, idx];
    } else {
      pollChoices = [idx];
    }
  }

  async function submitVote() {
    if (!poll || pollVoting || pollChoices.length === 0) return;
    pollVoting = true;
    try {
      poll = await api.votePoll(poll.id, pollChoices);
    } catch {
      // 投票に失敗したら選択は残したまま、また押せる状態に戻す。
    } finally {
      pollVoting = false;
    }
  }
</script>

{#if status.reblog}
  <!-- ブースト: 上に「○○がブースト」を出し、中身は元の status をそのまま描く。
       返信・ブースト等のアクションは入れ子側（本物のノート）に効く。 -->
  <div class="boost">
    <a class="boost-by" href={`/@${status.account.acct}`}>
      🔁 {@html renderEmojis(phrase(name), status.account.emojis)} がブースト
    </a>
    <Self status={status.reblog} {canReply} {onreply} {onupdate} {ondelete} />
  </div>
{:else}
<article class="status">
  {#if avatar}
    <img class="avatar" src={avatar} alt="" loading="lazy" />
  {:else}
    <span class="avatar" aria-hidden="true"></span>
  {/if}

  <div class="body">
    <header class="meta">
      <a class="display-name" href={`/@${status.account.acct}`}
        >{@html renderEmojis(phrase(name), status.account.emojis)}</a
      >
      <a href={`/@${status.account.acct}`}>@{status.account.acct}</a>
      <span>·</span>
      <a class="timestamp" href={`/@${status.account.acct}/${status.id}`} title={status.created_at}>{ts}</a>
    </header>

    {#if status.spoiler_text}
      <details>
        <summary>{status.spoiler_text}</summary>
        <div class="content">{@html renderEmojis(status.content, status.emojis)}</div>
      </details>
    {:else}
      <div class="content">{@html renderEmojis(status.content, status.emojis)}</div>
    {/if}

    {#if status.quote}
      <a class="quote-card" href={`/@${status.quote.account.acct}/${status.quote.id}`}>
        <div class="quote-head">
          {#if status.quote.account.avatar}
            <img class="quote-avatar" src={status.quote.account.avatar} alt="" loading="lazy" />
          {/if}
          <span class="quote-name"
            >{@html renderEmojis(
              phrase(status.quote.account.display_name || status.quote.account.username),
              status.quote.account.emojis
            )}</span
          >
          <span class="quote-acct">@{status.quote.account.acct}</span>
        </div>
        <div class="quote-content">{@html renderEmojis(status.quote.content, status.quote.emojis)}</div>
      </a>
    {/if}

    {#if status.media_attachments.length > 0}
      <div class="media">
        {#each status.media_attachments as m (m.id)}
          {#if m.type === 'image'}
            <img src={m.preview_url || m.url} alt={m.description || ''} loading="lazy" />
          {:else if m.type === 'video' || m.type === 'gifv'}
            <!-- gifv は無音ループ動画。ふつうの動画は controls を出す。 -->
            <video
              src={m.url}
              poster={m.preview_url || undefined}
              controls={m.type === 'video'}
              autoplay={m.type === 'gifv'}
              loop={m.type === 'gifv'}
              muted={m.type === 'gifv'}
              playsinline
              preload="metadata"
              aria-label={m.description || ''}
            ></video>
          {:else if m.type === 'audio'}
            <audio src={m.url} controls preload="metadata" aria-label={m.description || ''}></audio>
          {:else}
            <!-- 未知の型でも黙って捨てず、せめてリンクで残す。 -->
            <a class="media-fallback" href={m.url} target="_blank" rel="noopener noreferrer">
              {m.description || '添付ファイルを開く'}
            </a>
          {/if}
        {/each}
      </div>
    {/if}

    {#if poll}
      <div class="poll" aria-label="投票">
        {#if pollClosed}
          {#each poll.options as opt, i (i)}
            {@const votes = opt.votes_count ?? 0}
            {@const pct = Math.round((votes / pollTotal) * 100)}
            <div class="poll-result" class:mine={poll.own_votes?.includes(i)}>
              <div class="poll-bar" style={`width: ${pct}%`}></div>
              <span class="poll-label">{opt.title}</span>
              <span class="poll-pct">{pct}%</span>
            </div>
          {/each}
        {:else}
          {#each poll.options as opt, i (i)}
            <label class="poll-choice">
              <input
                type={poll.multiple ? 'checkbox' : 'radio'}
                name={`poll-${poll.id}`}
                checked={pollChoices.includes(i)}
                onchange={() => toggleChoice(i)}
              />
              <span>{opt.title}</span>
            </label>
          {/each}
          <button
            type="button"
            class="chip"
            disabled={pollVoting || pollChoices.length === 0}
            onclick={submitVote}
          >
            {pollVoting ? '送っています…' : '投票する'}
          </button>
        {/if}
        <p class="poll-meta">
          {poll.votes_count} 票{poll.expired ? '・締め切りました' : ''}
        </p>
      </div>
    {/if}

    {#if reactions.length > 0}
      <div class="reactions" aria-label="リアクション">
        {#each reactions as r (r.name)}
          <button
            type="button"
            class="reaction-chip"
            class:me={r.me}
            title={r.name}
            onclick={() => toggleReaction(r.name)}
          >
            {#if r.url}
              <img class="emoji" src={r.url} alt={r.name} loading="lazy" />
            {:else}
              <span class="emoji">{r.name}</span>
            {/if}
            <span class="count">{r.count}</span>
          </button>
        {/each}
      </div>
    {/if}

    <footer class="status-actions">
      <button type="button" class="chip" onclick={() => (pickerOpen = !pickerOpen)} aria-haspopup="dialog">
        ＋
      </button>
      <button
        type="button"
        class="chip"
        class:active={favourited}
        onclick={toggleFavourite}
        aria-pressed={favourited}
      >
        ⭐ {favCount > 0 ? favCount : ''}
      </button>
      <button
        type="button"
        class="chip"
        class:active={reblogged}
        onclick={toggleReblog}
        aria-pressed={reblogged}
        aria-label="ブースト"
      >
        🔁 {reblogCount > 0 ? reblogCount : ''}
      </button>
      <button
        type="button"
        class="chip"
        class:active={bookmarked}
        onclick={toggleBookmark}
        aria-pressed={bookmarked}
        aria-label={bookmarked ? 'ブックマークを外す' : 'ブックマーク'}
      >
        {bookmarked ? '🔖' : '🏷'}
      </button>
      {#if canReply}
        <button type="button" class="chip" onclick={() => onreply?.(status)}>
          返信
        </button>
      {/if}
      {#if mine || loggedIn}
        <button
          type="button"
          class="chip"
          onclick={() => (menuOpen = !menuOpen)}
          aria-haspopup="menu"
          aria-expanded={menuOpen}
          aria-label="その他の操作"
        >
          ⋯
        </button>
      {/if}
    </footer>

    {#if pickerOpen}
      <div class="picker-anchor">
        <ReactionPicker onpick={pickFromPicker} onclose={() => (pickerOpen = false)} />
      </div>
    {/if}

    {#if menuOpen}
      <div class="menu" role="menu">
        {#if mine}
          <button type="button" class="menu-item" role="menuitem" onclick={togglePin}>
            {pinned ? '📌 ピン留めを外す' : '📌 ピン留め'}
          </button>
          <button
            type="button"
            class="menu-item danger"
            role="menuitem"
            onclick={remove}
            disabled={deleting}
          >
            🗑 削除
          </button>
        {:else}
          <button
            type="button"
            class="menu-item"
            role="menuitem"
            onclick={doReport}
            disabled={reported}
          >
            {reported ? '🚩 通報しました' : '🚩 通報'}
          </button>
        {/if}
      </div>
    {/if}
  </div>
</article>
{/if}

<style>
  .boost-by {
    display: block;
    padding: 0.25rem 1rem 0;
    font-size: 0.8rem;
    color: var(--color-text-muted, #888);
    text-decoration: none;
  }

  .boost-by:hover {
    text-decoration: underline;
  }

  .quote-card {
    display: block;
    margin-top: 0.5rem;
    padding: 0.5rem 0.75rem;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    text-decoration: none;
    color: inherit;
  }
  .quote-card:hover {
    background: rgba(127, 127, 127, 0.08);
  }
  .quote-head {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    margin-bottom: 0.25rem;
    font-size: var(--text-sm);
  }
  .quote-avatar {
    width: 1.25rem;
    height: 1.25rem;
    border-radius: 50%;
    object-fit: cover;
  }
  .quote-name {
    font-weight: 600;
  }
  .quote-acct {
    color: var(--color-text-muted);
  }
  .quote-content {
    font-size: var(--text-sm);
  }

  .reactions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.25rem;
    margin-top: 0.5rem;
  }
  .reaction-chip {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
    padding: 0.125rem 0.5rem;
    border-radius: 999px;
    background: var(--reaction-bg, rgba(127, 127, 127, 0.12));
    border: 1px solid transparent;
    font-size: 0.875rem;
    line-height: 1.4;
    cursor: pointer;
  }
  .reaction-chip:hover {
    background: var(--reaction-bg-hover, rgba(127, 127, 127, 0.2));
  }
  .reaction-chip.me {
    background: var(--reaction-bg-me, rgba(99, 102, 241, 0.18));
    border-color: var(--reaction-border-me, rgba(99, 102, 241, 0.5));
  }
  .reaction-chip .emoji {
    font-size: 1rem;
  }
  .reaction-chip img.emoji {
    width: 1.125rem;
    height: 1.125rem;
    vertical-align: -0.2em;
  }
  .reaction-chip .count {
    font-variant-numeric: tabular-nums;
    color: var(--muted, #666);
  }
  .status-actions .chip.active {
    background: var(--reaction-bg-me, rgba(99, 102, 241, 0.18));
  }
  .picker-anchor {
    position: relative;
    margin-top: 0.25rem;
  }

  .menu {
    display: flex;
    flex-direction: column;
    align-items: stretch;
    gap: 0.125rem;
    margin-top: 0.25rem;
    padding: 0.25rem;
    width: max-content;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    background: var(--color-bg, #fff);
  }
  .menu-item {
    padding: 0.375rem 0.5rem;
    border: none;
    border-radius: var(--radius-sm);
    background: none;
    font: inherit;
    color: inherit;
    text-align: left;
    cursor: pointer;
  }
  .menu-item:hover:not(:disabled) {
    background: rgba(127, 127, 127, 0.12);
  }
  .menu-item.danger:hover:not(:disabled) {
    background: rgba(220, 38, 38, 0.14);
  }
  .menu-item:disabled {
    opacity: 0.6;
    cursor: default;
  }

  .media video,
  .media audio {
    max-width: 100%;
    border-radius: var(--radius-sm);
  }
  .media-fallback {
    display: inline-block;
    margin-top: 0.25rem;
    font-size: var(--text-sm);
  }

  .poll {
    margin-top: 0.5rem;
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
  }
  .poll-choice {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    cursor: pointer;
  }
  .poll-result {
    position: relative;
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.25rem 0.5rem;
    border-radius: var(--radius-sm);
    overflow: hidden;
    background: rgba(127, 127, 127, 0.08);
  }
  .poll-bar {
    position: absolute;
    inset: 0 auto 0 0;
    background: var(--reaction-bg-me, rgba(99, 102, 241, 0.18));
    z-index: 0;
  }
  .poll-result.mine .poll-bar {
    background: var(--reaction-border-me, rgba(99, 102, 241, 0.5));
  }
  .poll-label,
  .poll-pct {
    position: relative;
    z-index: 1;
  }
  .poll-label {
    flex: 1;
  }
  .poll-pct {
    font-variant-numeric: tabular-nums;
  }
  .poll-meta {
    font-size: var(--text-sm);
    color: var(--color-text-muted, #666);
  }
</style>
