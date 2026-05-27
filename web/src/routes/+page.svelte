<script lang="ts">
  import { onMount } from 'svelte';
  import { isLoggedIn } from '$lib/auth';
  import { goto } from '$app/navigation';
  import LaneDoor from '$lib/components/LaneDoor.svelte';

  onMount(() => {
    if (isLoggedIn()) {
      goto('/timeline');
    }
  });

  // 「入る」は /login (server-rendered, PoW なし) に直接飛ばす。
  // ログイン form 送信後に /check?intent=login に redirect されて、
  // そこで初めて Anubis の PoW が走る ─ ユーザが何もしないうちに
  // 確認を要求しない作り。
</script>

<section class="hero">
  <h1>ここは、しずかな Fediverse のお家です。</h1>
  <p class="tagline">
    すぐとなりに、ちょこんとすわって、人の話をきいたり、ときどき、自分のことを言ったりする場所。
  </p>
</section>

<section class="section">
  <div class="doors">
    <LaneDoor
      href="/signup"
      lane="use"
      title="はじめる"
      description="招待コードを持っていれば、ここで作れます。"
    />
    <a class="lane-door" data-lane="build" href="/login" data-sveltekit-reload>
      <h3>入る</h3>
      <p>もう住んでいる人は、こちらから。</p>
    </a>
  </div>
</section>

<section class="section">
  <p class="prose-small">
    sukhi-fedi は、ActivityPub に話せる Fediverse のサーバ。Mastodon や Misskey と
    つながっています。ここで作ったアカウントから、遠くの人の言葉をきいて、近くにいる
    人と話せます。
  </p>
</section>

