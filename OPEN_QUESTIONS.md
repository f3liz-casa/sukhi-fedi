# Open questions

TODO.md からの設計判断待ち項目。実装に入る前に方針を確定したい論点を
ここに集約する。各項目はゴール / 候補 / 推奨 / 影響範囲の順で書く。

凡例: **Recommended** は「迷ったらこれで進める」既定。実装を始めるときは
このファイルへの追記更新も含めて確定させる。

---

## Q1. Search 戦略 — full-text どうやるか

**Goal.** `GET /api/v2/search` の `type=statuses` を機能させる。
account / hashtag は既存テーブルだけで足りるので別問題。

**候補:**

1. **PostgreSQL `tsvector` カラム + GIN index on `notes.content`**（**Recommended**）。
   外部依存ゼロ。日本語は `pg_bigm` か `pgroonga` 拡張で形態素なし n-gram。
   分散書き込みの一貫性ハザードなし(同一 DB)。
2. **Meilisearch sidecar.** トピ重視ならランキングが楽。運用が増える
   (Docker サービス + outbox サブジェクト追加 + 再同期手順)。
3. **MVP として hashtag/account のみ返して `statuses: []`** で逃げる。
   Mastodon 互換テストは通る。要件次第。

**影響範囲.** 1 → `notes` migration + `Search` capability。
2 → 新 outbox subject + delivery 側 indexer + 検索 capability。
3 → capability 1 個のみ。

**未確定.** 日本語形態素は要るか? Misskey と比較する想定なら必要だが、
当面ローカル運用なら 3 → 後で 1 で十分。

---

## Q2. Streaming WebSocket — どこに置くか

**Goal.** `/api/v1/streaming` (home/public/list/hashtag)。

**候補:**

1. **Gateway 内 Bandit upgrade handler**（**Recommended**)。`Streaming`
   addon の NATS Registry / `stream.new_post` を既に持っているので、
   ws upgrade → subscribe → JSON 投げるだけ。新ノード不要。
2. **`:sukhi_api` 上の別 Bandit ポート.** 認可は OAuth bearer のままで
   揃う。API ノードに WS 状態を寄せられて gateway は AP 専業に。
3. **Bun に寄せる.** WS は得意。ただし pub/sub ブリッジを別途貼る必要、
   Erlang プロセスから直接 push できなくなる。

**影響範囲.** どれも `Streaming` addon の broadcaster は流用。
WS 接続のライフタイム管理(切断検知・ハートビート・バックプレッシャ)を
どの runtime に置くかの差。

**未確定.** API ノードと gateway は別ホストで動くデプロイがあるか?
あるなら 2、無いなら 1。

---

## Q3. Misskey native API — addon マニフェストの粒度

**Goal.** Misskey クライアント(MissCat 等)が `/api/i` から喋れる。

**候補:**

1. **単一 addon `:misskey_api` で全 capability を束ねる**（**Recommended**)。
   capability 名は `misskey.notes.create` のような名前空間で揃える。
   オン/オフが 1 フラグになり、運用が楽。
2. **機能ごとに分割** (`:misskey_auth`, `:misskey_notes`, `:misskey_reactions`)。
   段階リリースには良いが、依存解決が面倒。
3. **gateway 側にネイティブ実装.** `:sukhi_api` の view 分離思想と衝突。
   既存の view 戦略を崩す。却下。

**影響範囲.** `api/lib/sukhi_api/views/misskey_*.ex` 群 + `bun/addons/misskey_api/`。
`SukhiFedi.Notes/Timelines` は再利用。

**未確定.** Misskey のセッションキー(`/api/auth/session/*`)を OAuth トークン
として保存して良いか? スキーマ的には `oauth_access_tokens` に乗るが、
Misskey 仕様の `permission: ["read:account", …]` を scope にどう写すかが要設計。

---

## Q4. DM (`visibility: "direct"`) — 宛先解決

**Goal.** Misskey からのチャット相当を受信できる + ローカルから送信できる。

**候補:**

1. **本文の `@user@host` を mention 抽出 → addressing は to: 各 actor URI のみ**
   (**Recommended**)。Mastodon と同じ。`cc` は空、Public 非含。
2. **`ConversationParticipant` 駆動.** 既存テーブルがあるが、最初の DM
   をどう発火するかが鶏卵。1 で作って後から会話統合する形が現実的。
3. **Misskey の `visibility: "specified"` ネイティブ受け.** Bun の `dm`
   translator はあるが、`visibleUserIds` を gateway 側でどう正規化するか
   未設計。短期は ActivityPub 正本にし、Misskey 拡張は後回し。

**影響範囲.** gateway: `Notes.create_status/2` に mention 抽出 + addressing
ロジック、`Notes` のスキーマで visibility="direct" 解禁。
outbox: 新 subject `sns.outbox.dm.created` か、既存 `note.created` の
payload で audience を運ぶか。delivery: 既存 fan-out で十分。

**未確定.** mention は actor URI / handle どちらをカノニカルにする?
`Note` に `mentions` JSONB を持たせる必要があるか(あると Mastodon view
の `mentions[]` がタダで埋まる)。

---

## Q5. メディア >8 MiB — presigned URL の capability 形

**Goal.** 大ファイルを `:sukhi_api` を経由させずに S3 直 PUT。

**候補:**

1. **`POST /api/v2/media` → 既存と同じ。`POST /api/v2/media?upload=presigned`
   で `{upload_url, fields, media_id}` を返す**（**Recommended**)。
   クライアントが直 PUT → 完了後 `POST /api/v1/media/:id/finalize` で確定。
2. **TUS プロトコル.** Mastodon は採用していない。互換性のため却下。
3. **既存の 8 MiB 上限のまま据え置く.** `MEDIA_DIR` で当面回す。

**影響範囲.** `:sukhi_api` capability 2 個 + S3 SDK 依存追加。
`SukhiFedi.Addons.Media.generate_upload_url/3` は既存なのでブリッジのみ。

**未確定.** S3 / MinIO / R2 のどれを想定する? credential 配り方は env か
IAM role か。MVP は env でいい。

---

## Q9. Admin REST — `:admin_api` を新 addon にするか

**Goal.** `/api/v1/admin/*` のスコープ整理。block/mute/report/
domain_blocks のユーザー面はすでに `MastodonModeration` capability で
公開済み(`Moderation` addon に乗せている)。admin 面は権限スコープが
別物なので扱いを揃える必要がある。

**候補:**

1. **新 addon `:admin_api`** を切り出して `Moderation` の admin 系
   capability をそこへ分離(**Recommended**)。`enabled_addons` で
   admin 面だけオン/オフできる。
2. **`Moderation` のまま admin 系も同居.** capability を 1 ファイルに
   まとめて運用シンプル。スコープは route 単位で分かれる。
3. **両方コア化.** addon 思想が崩れる。却下。

**影響範囲.** 1 → 新 addon ファイル + capability 群 +
`SukhiFedi.Addons.Moderation` の admin ヘルパーを移譲。

---

## 結論を要するメタ問い

- **`/goal` で言う「Misskey と通信できる」のスコープは「フォロー +
  受信 + 投稿 + 通知 + reblog/like 通知」まで達成(現状)。残るのは
  DM (Q4) と Misskey ネイティブ surface (Q3)。どちらを次にする?**
- **デプロイは 1 ホスト想定か複数ホストか?** Q2 (streaming 配置) の
  答えが変わる。
- **検索の主目的は誰の体験か?** 自分のタイムライン振り返り→ FTS 不要、
  サーバー横断検索→ Meilisearch、Q1 の判定が変わる。
