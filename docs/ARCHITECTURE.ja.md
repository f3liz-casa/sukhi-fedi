# sukhi-fedi のかたち

> **これが設計の教科書だよー。** 新しく来た人がこのファイルとコードだけ見て、
> ゼロから作り直せる — それが目標。併読するなら
> [`ADDONS.md`](ADDONS.md) だけ（アドオンABIのお約束ごと）。
>
> 英語の正本は [`ARCHITECTURE.md`](ARCHITECTURE.md)。ズレてたら英語側を信じてね。

## 1. なにを作ってるの？

`sukhi-fedi` は **ActivityPub な連合SNSサーバー**。Mastodon互換 +
Misskey互換のAPIを喋るよ。ローカルにログインして、Noteを投稿して、
リモートのアクターをフォローして、世界中のFediverseサーバーから
流れてくる投稿を受け取る、あの感じ。

設計の北極星：
**Elixirゲートウェイが1個 + Bunワーカー群（ステートレス） + 分散Erlangのプラグインノード1個**、
それを **PostgreSQL（真実の源）と NATS（イベントの通り道）** で束ねる。
それ以外は必須依存にしない、って決めてる。

## 2. 誰がなにを持ってるの？

```
 ユーザー (HTTPS)        他のサーバー (HTTPS)
      │                       │
      ▼                       ▼
 ╔══════════════════════════════════════════════╗
 ║           Elixir — 案内人 + 配達員            ║
 ║  Bandit/Plug / WebSocket ストリーミング        ║
 ║  OAuth / WebAuthn / セッション                 ║
 ║  inbox POST の受付 + ディスパッチ              ║
 ║  Outbox.Relay（LISTEN/NOTIFY → JetStream）    ║
 ║  Oban 配信ワーカー（HTTP POST + リトライ）     ║
 ║  WebFinger / NodeInfo（直接、プロキシなし）    ║
 ║  /api/v1 と /api/admin をプラグインノードへ    ║
 ╚═════════════════════════════════╤════════════╝
                                   │
      PostgreSQL（真実の源、Ecto経由）
      + outbox テーブル（実質exactly-once）
      + delivery_receipts（inbox単位の冪等性）
                                   │
      NATS JetStream
      ├─ stream OUTBOX        (sns.outbox.>)
      └─ stream DOMAIN_EVENTS (sns.events.>)
                                   │
                ┌──────────────────┼──────────────────┐
                ▼                                     ▼
 ╔══════════════════════════════════╗  ╔═════════════════════════════╗
 ║      Bun — 翻訳家 + 印鑑職人      ║  ║   api — REST プラグインノード ║
 ║  NATS Micro サービス "fedify"    ║  ║  （:sukhi_api、BEAMノード） ║
 ║    fedify.translate.v1           ║  ║  ゲートウェイから :rpc で叩く ║
 ║    fedify.sign.v1                ║  ║  Mastodon / Misskey API     ║
 ║    fedify.verify.v1              ║  ║  capability を自動登録       ║
 ║    fedify.ping.v1                ║  ║                             ║
 ║  キューグループ "fedify-workers" ║  ║                             ║
 ║  HTTPサーバーは持たない — NATS専用 ║  ║                             ║
 ╚══════════════════════════════════╝  ╚═════════════════════════════╝
```

この分け方で守ってるお約束:

1. **外の世界とHTTPを喋るのはElixirだけ**。ユーザーも他サーバーも。
   BunはHTTPサーバー持ってない。
2. **Postgresに書き込むのもElixirだけ**。Bunはステートレス。
3. **外向き配信は全部 Elixir の Oban を通す** — Bunじゃない。
   BEAMの軽量プロセスなら数千フォロワーへのファン・アウトも余裕。
   Bunのシングルスレッド・イベントループは詰まっちゃう。
4. **BunはJSON-LDとHTTP署名だけ担当**。Fedifyが得意な領域がちょうどここ。
5. **Mastodon/Misskey REST は api プラグインノードで動く**。ゲートウェイとは
   分散Erlang の `:rpc` で繋がる — HTTPホップなし、NATSエンベロープなし。

## 3. ディレクトリの地図

```
sukhi-fedi/
├── elixir/                                # 案内人 + 配達員
│   ├── lib/sukhi_fedi/
│   │   ├── application.ex                 # 監視ツリー
│   │   ├── addon.ex / addon/registry.ex   # アドオンABI + 発見
│   │   ├── repo.ex
│   │   ├── outbox.ex                      # Outbox.enqueue / enqueue_multi
│   │   ├── outbox/relay.ex                # LISTEN/NOTIFY → JetStream
│   │   ├── delivery/
│   │   │   ├── fedify_client.ex           # NATS Micro クライアント → Bun
│   │   │   ├── worker.ex                  # Oban 配信ワーカー
│   │   │   ├── fan_out.ex                 # 事前計算 + Oban.insert_all
│   │   │   ├── followers_sync.ex          # FEP-8fcf
│   │   │   └── follower_sync_worker.ex
│   │   ├── federation/actor_fetcher.ex    # リモートactor取得 + ETSキャッシュ
│   │   ├── schema/                        # Ectoスキーマ（note, account,
│   │   │   │                                follow, boost, reaction, …）
│   │   │   ├── outbox_event.ex            # `outbox` テーブル
│   │   │   └── delivery_receipt.ex
│   │   ├── cache/ets.ex                   # ETS TTLキャッシュ
│   │   ├── ap/                            # ActivityPub ヘルパー
│   │   │   ├── client.ex                  # レガシーNATS req/reply (ap.*)
│   │   │   └── instructions.ex            # inboxアクティビティのディスパッチャ
│   │   ├── nats/                          # db.* トピックハンドラ
│   │   │   ├── helpers.ex
│   │   │   ├── accounts.ex
│   │   │   ├── notes.ex
│   │   │   ├── content.ex
│   │   │   └── admin.ex
│   │   ├── addons/                        # ファーストパーティのアドオン
│   │   │   ├── nodeinfo_monitor.ex + nodeinfo_monitor/
│   │   │   ├── streaming.ex + streaming/
│   │   │   ├── articles / bookmarks / feeds / media / mfm / …
│   │   └── web/                           # コントローラ + plug
│   │       ├── router.ex
│   │       ├── rate_limit_plug.ex
│   │       ├── plugin_plug.ex             # api プラグインノードへ :rpc
│   │       ├── inbox_controller.ex
│   │       ├── collection_controller.ex   # followers / following collection
│   │       └── …
│   ├── priv/repo/migrations/
│   │   ├── core/                          # コアスキーマ
│   │   └── addons/<id>/                   # アドオン別マイグレーション
│   ├── test/                              # unit + integration
│   ├── config/{config,dev,prod,runtime,test}.exs
│   └── mix.exs / Dockerfile
│
├── bun/                                   # 翻訳家 + 印鑑職人
│   ├── services/fedify_service.ts         # ★ NATS Micro サービス本体
│   ├── main.ts                            # レガシー ap.verify + ap.inbox
│   ├── handlers/
│   │   ├── build/{note,follow,accept,announce,actor,dm,collection_op,
│   │   │           like,undo,delete}.ts   # 1タイプ1トランスレータ
│   │   ├── verify.ts                      # HTTP署名の検証
│   │   ├── sign_delivery.ts               # HTTP署名の付与
│   │   └── inbox.ts / inbox_test.ts       # レガシー ap.inbox
│   ├── fedify/
│   │   ├── context.ts                     # cachedDocumentLoader
│   │   ├── keys.ts                        # ローカルアクターの鍵ストア（作成用）
│   │   ├── key_cache.ts                   # CryptoKeyキャッシュ（署名パス）
│   │   └── utils.ts                       # signAndSerialize, injectDefined, …
│   ├── addons/
│   │   ├── loader.ts                      # ABIチェック + 有効/無効フィルタ
│   │   ├── types.ts                       # BunAddon + TranslateHandler
│   │   ├── mastodon_api/manifest.ts
│   │   └── misskey_api/manifest.ts
│   ├── package.json                       # TS 6.0.3, @fedify/fedify 1.x,
│   │                                        @js-temporal/polyfill, @nats-io/*
│   ├── tsconfig.json
│   └── Dockerfile                         # oven/bun:1-alpine
│
├── api/                                   # ★ Mastodon/Misskey REST プラグインノード
│   ├── mix.exs                            # 独立した :sukhi_api アプリ
│   ├── lib/sukhi_api/
│   │   ├── application.ex
│   │   ├── capability.ex                  # @behaviour + use マクロ
│   │   ├── registry.ex                    # capability の自動発見
│   │   ├── router.ex                      # :rpc 入口
│   │   ├── gateway_rpc.ex                 # ゲートウェイに :rpc で戻る
│   │   └── capabilities/                  # ← ここにファイル置くとエンドポイント増える
│   │       ├── mastodon_instance.ex
│   │       └── nodeinfo_monitor.ex
│   └── Dockerfile
│
├── infra/
│   ├── nats/bootstrap.sh                  # JetStreamストリームのブート
│   └── terraform/ · ansible/              # infra-as-code (OCI)
│
├── docker-compose.yml                     # 開発+本番スタック（GHCRイメージ固定）
├── docker-compose.test.yml                # 密閉テストスタック
└── docs/
    ├── ARCHITECTURE.md                    # 英語正本
    ├── ARCHITECTURE.ja.md                 # ← ここ
    └── ADDONS.md                          # アドオンABI
```

## 4. NATS のトポロジー

### 4.1 JetStream ストリーム

`infra/nats/bootstrap.sh` が宣言的に作ってくれる（composeでは
`nats-bootstrap` サイドカーが走らせる）。

| ストリーム         | Subject          | 保存   | 保持       | ひとこと                                               |
| ------------------ | ---------------- | ------ | ---------- | ------------------------------------------------------ |
| `OUTBOX`           | `sns.outbox.>`   | file   | WorkQueue  | 実質exactly-onceのリレー。fan-out / timeline 消費      |
| `DOMAIN_EVENTS`    | `sns.events.>`   | file   | Limits 7d  | WebSocket・通知用のブロードキャスト                    |

`dupe-window = 2m` と `Nats-Msg-Id = outbox-<id>` の組み合わせで
ストリーム側の重複排除も効くよ。

### 4.2 Subject の命名規則

```
sns.<コンテキスト>.<集約>.<操作>[.<バリアント>]
```

| Subject                            | 向き | 発行元                        | 消費側                       |
| ---------------------------------- | ---- | ----------------------------- | ---------------------------- |
| `sns.outbox.note.created`          | pub  | `Notes.create_note/1`         | deliverer / timeline-updater |
| `sns.outbox.note.deleted`          | pub  | `Notes.delete_note/1`         | deliverer                    |
| `sns.outbox.follow.requested`      | pub  | `Social.follow/2`             | deliverer                    |
| `sns.outbox.like.created`          | pub  | `Notes.create_like/2`         | deliverer                    |
| `sns.outbox.like.undone`           | pub  | `Notes.delete_like/2`         | deliverer                    |
| `sns.outbox.announce.created`      | pub  | `Notes.create_boost/2`        | deliverer                    |
| `sns.events.timeline.home.updated` | pub  | timeline-updater (addon)      | streaming-fanout             |
| `sns.events.notification.mention`  | pub  | inbox ハンドラ                | streaming-fanout             |

### 4.3 NATS Micro サービス（Bun側）

サービス名 `fedify`、バージョン `0.2.0`、キューグループ `fedify-workers`。
Bunのレプリカを増やすとNATS Microが自動でロードバランスしてくれる。

| エンドポイント         | リクエスト                                                   | レスポンス                          |
| ---------------------- | ------------------------------------------------------------ | ----------------------------------- |
| `fedify.ping.v1`       | 生バイト                                                     | そのままエコー（ヘルスチェック）     |
| `fedify.translate.v1`  | `{object_type, payload}`                                     | `{ok:true, data:{…}}`               |
| `fedify.sign.v1`       | `{actorUri, inbox, body, privateKeyJwk, keyId, algorithm?}`  | `{ok:true, data:{headers:{…}}}`     |
| `fedify.verify.v1`     | `{method, url, headers, body}`                               | `{ok:true, data:{ok:bool, …}}`      |

`translate` のコア `object_type`（`bun/services/fedify_service.ts`）:
`note`, `follow`, `accept`, `announce`, `actor`, `dm`, `add`, `remove`,
`like`, `undo`, `delete`。アドオンは `<addon_id>.<type>` という
名前空間付きキーで追加する — コアキーの上書きは起動時に
`addons/loader.ts` が弾くよ。

サービスディスカバリは NATS Micro が自動で
`$SRV.{PING,INFO,STATS}.fedify` を公開してくれる。

### 4.4 レガシーなNATS面

段階的リファクタの名残で、まだ生きてる古いルートが2つあるよ:

- **`ap.verify` / `ap.inbox`**（`bun/main.ts`） — 入ってくる署名検証と
  inboxアクティビティのディスパッチ。inbox コントローラは
  `SukhiFedi.AP.Client.request/2` でここを呼んでる。他のap.*は
  全部 `fedify.*` に卒業済み。
- **`db.>`**（`SukhiFedi.Web.DbNatsListener`） — Postgresへの読み書きの
  req/reply。昔BunのHTTP API層がいたときの窓口。HTTP層自体は3-bで消えて
  いるけど、api プラグインノードと一部アドオンが手軽なRPCとして
  まだ使ってるから残してる。ハンドラは
  `SukhiFedi.Nats.{Accounts, Notes, Content, Admin}`。

## 5. Transactional Outbox（とっても大事）

ここをサボると「DB insert + NATS pub」が2つの独立書き込みになって、
その間でクラッシュするとイベントが消えるか重複する。だからここは
譲れないパターンなのだ。

### 5.1 スキーマ

マイグレーション `core/20260420000001_create_outbox.exs`:

```
outbox(
  id bigserial PRIMARY KEY,
  aggregate_type text NOT NULL,    -- "note", "follow", …
  aggregate_id   text NOT NULL,
  subject        text NOT NULL,    -- "sns.outbox.note.created" 等
  payload        jsonb NOT NULL,
  headers        jsonb NOT NULL DEFAULT '{}',
  status         text NOT NULL DEFAULT 'pending',  -- pending | published | failed
  attempts       integer NOT NULL DEFAULT 0,
  last_error     text,
  inserted_at    timestamptz NOT NULL DEFAULT now(),
  published_at   timestamptz
)
-- 部分インデックス — published 行が増えてもホットセットが小さいまま
create index(:outbox, [:id], where: "status = 'pending'")
create index(:outbox, [:aggregate_type, :aggregate_id])

-- ステートメント単位のトリガー（行単位じゃない）。
-- bulk INSERT しても 1 INSERT 文あたり NOTIFY は1回だけ。
AFTER INSERT ON outbox FOR EACH STATEMENT EXECUTE FUNCTION outbox_notify();
```

`core/20260420000005_add_hot_path_indexes.exs` で、部分インデックスへの
差し替えと `FOR EACH STATEMENT` トリガーへの切り替えを一気にやってる。
同じマイグレで `notes(visibility, created_at)` (publicタイムライン用)、
`follows(followee_id, state)` / `follows(follower_uri, state)`（FEP-8fcf と
「誰をフォロー？」系のパス用）も入れてる。

`delivery_receipts`（マイグレ `core/20260420000002`）:

```
delivery_receipts(
  id bigserial PRIMARY KEY,
  activity_id  text NOT NULL,   -- ActivityPub Activity id
  inbox_url    text NOT NULL,
  status       text NOT NULL,   -- delivered | failed | gone
  delivered_at timestamptz,
  inserted_at  timestamptz NOT NULL
)
unique_index(delivery_receipts, [activity_id, inbox_url])
```

### 5.2 書き込み側（プロデューサー）

連合に流す必要がある全ての書き込みは `SukhiFedi.Outbox.enqueue_multi/6`
を Ecto.Multi の中でドメインinsertと一緒に使う:

```elixir
Ecto.Multi.new()
|> Ecto.Multi.insert(:note, Note.changeset(%Note{}, attrs))
|> Outbox.enqueue_multi(:outbox_event,
     "sns.outbox.note.created", "note",
     & &1.note.id,
     fn %{note: note} -> %{note_id: note.id, …} end)
|> Repo.transaction()
```

DBコミット ⇒ outbox行は永続化。それだけ。

現状の呼び出し元:
- `SukhiFedi.Notes.create_note/1`  → `sns.outbox.note.created`
- `SukhiFedi.Notes.delete_note/1`  → `sns.outbox.note.deleted`
- `SukhiFedi.Notes.create_like/2`  → `sns.outbox.like.created`
- `SukhiFedi.Notes.delete_like/2`  → `sns.outbox.like.undone`
- `SukhiFedi.Notes.create_boost/2` → `sns.outbox.announce.created`
- `SukhiFedi.Social.follow/2`      → `sns.outbox.follow.requested`

### 5.3 リレー側（outbox消費 → NATS発行）

`SukhiFedi.Outbox.Relay` は監視ツリー内のシングルトンGenServer:

1. 起動時: `Postgrex.Notifications.listen/2` で `outbox_new` を購読 →
   すぐに1回tickして前プロセスの取りこぼしを拾う。
2. 起床トリガー: トリガーからのNOTIFY、または30秒のフォールバックタイマー。
3. 1tickごとに:
   ```
   SELECT FROM outbox WHERE status='pending' AND attempts<10
   ORDER BY id LIMIT 100 FOR UPDATE SKIP LOCKED
   ```
   — `SKIP LOCKED` のおかげで将来複数リレーが同時に走っても安全。
4. 取った行ごとに `Gnat.pub/4` で JetStreamへ発行。ヘッダに
   `Nats-Msg-Id: outbox-<id>`（重複排除のため）。
5. 結果をバケット分けしてtick終了:
   - 成功は全idまとめて1回の `update_all` で
     `status='published', published_at=now()`。
   - 失敗は行ごとに更新（`last_error` が行ごとに違うし、このパスは
     `max_attempts=10` で上限がある）。リトライ上限に達したら
     `status='failed'` に切り替え。

## 6. エンドツーエンドの流れ

### 6.1 ローカルユーザーがNoteを投稿

```
POST /api/v1/statuses
   │  (router.ex の /api/v1/*_ にマッチ → PluginPlug → :rpc で api ノード)
   │   向こうのcapabilityが gateway_rpc を通して
   │   SukhiFedi.Notes.create_note/1 を呼ぶ。
   ▼
Elixir Notes.create_note/1
   Ecto.Multi:
     insert notes
     insert outbox(sns.outbox.note.created)
   commit  ──▶ AFTER INSERT STATEMENT TRIGGER が NOTIFY outbox_new
                         │
                         ▼
              Outbox.Relay（起きる）
                         │  Gnat.pub で JetStream OUTBOX へ
                         ▼
         （今後の消費者: ap-deliverer が OUTBOX を読んで
          Delivery.FanOut.enqueue/2 を呼ぶ）
                         │  各フォロワーのinboxにファン・アウト
                         ▼
         Delivery.FanOut.enqueue(object, inbox_urls)
           1. Objectのraw_jsonを1回だけ読む
           2. FEP-8fcfのheader_value(actor_uri)を1回だけ計算
           3. job args を作成:
              {raw_json, actor_uri, activity_id, sync_header, inbox_url}
           4. Oban.insert_all — ファン・アウトごとに1 INSERT、
              inbox数じゃなくて！
                         │
                         ▼ （inboxごとにOban job 1個）
         Delivery.Worker (Oban queue :delivery, max_attempts 10)
          1. delivery_receipts(activity_id, inbox_url) で配信済みか確認
          2. args["raw_json"] からbody復元（DBアクセスなし）
          3. args["sync_header"] から Collection-Synchronization ヘッダを付与
          4. FedifyClient.sign(...) で署名 → NATS Microで Bun に。
             Bun 側は bun/fedify/key_cache.ts のキャッシュされた
             CryptoKey を使うよ
          5. Req.post でinbox_url へ（Finch pool 50×4、ホストごと）
          6. 2xxならdelivery_receipt 記録
          7. エラーならObanの指数バックオフ、最大10回まで
```

ファン・アウトをまたいで不変になる仕事（body encode、フォロワー
ダイジェスト、署名鍵のimport）は、配信1回ずつじゃなくてアクティビティ
1回につき1回に集約されるようになってる。事前計算は
`SukhiFedi.Delivery.FanOut`、BunのCryptoKey再利用は
`bun/fedify/key_cache.ts`。

### 6.2 他のサーバーが私たちのinboxに配達

```
POST /users/alice/inbox  （外部のMastodon）
   │
   ▼
Elixir InboxController（生ボディとヘッダをキャプチャ）
   │
   ▼
AP.Client.request("ap.verify", {payload})
   │   レガシーNATS req/reply → Bun main.ts handleVerify
   │   {ok: true} or {ok: false}
   ▼
AP.Client.request("ap.inbox", {payload})
   │   レガシーNATS req/reply → Bun main.ts handleInbox
   │   Instructionsマップが返ってくる
   ▼
Instructions.execute(instruction)
   │   Follow / Accept / Create(Note) / Announce / Like / Delete / Undo
   │   + FEP-8fcf: リクエストにCollection-Synchronizationヘッダが
   │     付いてたら FollowerSyncWorker を積んで follows テーブルを整合
   ▼
DB書き込み + （時々）Oban ジョブ（例えば Accept を返送）
   │
   ▼
202 Accepted
```

`Instructions.execute/1` は他にも、入ってくる`Delete`でローカルの
objectミラーを掃除したり、`Undo(Follow)`でfollow行を消したりする。
DMは`visibility = "direct"`のローカルnoteにマテリアライズされて、
会話の参加者も記録される。

### 6.3 WebFinger（ローカルアクター探索）

```
GET /.well-known/webfinger?resource=acct:alice@example.tld
   ▼
WebfingerController（Elixir、Bunは呼ばない）
   1. acct をパース → username, domain
   2. domain == 自分のドメイン:
        Accounts.get_account_by_username/1
        JRDを組み立て（subject, links: self → actor URL）
        ETS :webfinger テーブルにキャッシュ（10分TTL）
   3. それ以外: 404（他所のwebfingerはプロキシしない）
```

### 6.4 NodeInfo

```
GET /.well-known/nodeinfo            → ディスカバリJSON（/nodeinfo/2.1へのリンク）
GET /nodeinfo/2.1                    → 静的情報（version, software, usage）
   ▼
NodeinfoController（Elixir、純関数）
```

### 6.5 followers / following コレクション

`GET /users/:name/followers` と `GET /users/:name/following` は
`SukhiFedi.Web.CollectionController` がJOIN 1発の
`Social.list_followers/2` / `Social.list_following/2` で返す —
アカウント情報を1件ずつ取りに行くようなN+1はなし。

## 7. アドオンシステム

3つの層それぞれがアドオンコードを持てる。同じidを宣言して、
`ENABLED_ADDONS` / `DISABLE_ADDONS` 環境変数を共有するよ。

### ゲートウェイ側（`elixir/lib/sukhi_fedi/`）

```elixir
defmodule SukhiFedi.Addons.Streaming do
  use SukhiFedi.Addon, id: :streaming
  @impl true
  def supervision_children,
    do: [SukhiFedi.Addons.Streaming.Registry, SukhiFedi.Addons.Streaming.NatsListener]
end
```

`SukhiFedi.Addon.Registry` が起動時に、コンパイル済みモジュールから
`@sukhi_fedi_addon` という永続属性を持ってるやつを全部探して、
各アドオンの `abi_version` のメジャーがコア（`"1"`）と合うか確認、
enable/disableフィルタをかけて、監視の子プロセスとNATS購読を返す。
メジャーバージョンが合わないと起動時にクラッシュ（それで安全）。
`priv/repo/migrations/addons/<id>/` のマイグレーションはリリース時に
アドオンごとに走る。

### Bun側（`bun/addons/`）

```ts
const myAddon: BunAddon = {
  id: "my_addon",
  abi_version: "1.0",
  translators: { "my_addon.widget": handleBuildWidget },
};
export default myAddon;
```

`bun/addons/loader.ts` の静的リストに登録（Bunのimportはコンパイル時
なのだ）。アドオンは `fedify.translate.v1` に新しいキーを足したり、
レガシー `ap.*` 購読を足したりできる。**コアのトランスレータは
上書きできない**ようになってる。

### APIプラグインノード側（`api/lib/sukhi_api/capabilities/`）

1ファイル1 capability。`use SukhiApi.Capability, addon: :mastodon_api`
でアドオンにタグ付け。タグなしはコア扱い（常に有効）。
`SukhiApi.Registry` が起動時に
`:application.get_key(:sukhi_api, :modules)` で発見して、同じ環境変数で
フィルタ。DBアクセスは `gateway_rpc` でゲートウェイに戻るから、
プラグインノードは自前のEctoプールを持たない。

ABIの全容は `docs/ADDONS.md` 参照ー。

## 8. APIプラグインノード（分散Erlang）

Mastodon / Misskey の REST 面は `api/` 配下の **独立BEAMノード**
として走る。ゲートウェイは `SukhiFedi.Web.PluginPlug` 経由で
`:rpc.call/5` する — HTTPホップなし、NATSエンベロープなし、
docker-composeネットワーク上の素のErlang Distributionだけ。

```
クライアント ──HTTPS──▶  Elixir ゲートウェイ (node gateway@elixir)
                         └─ router が "/api/v1/*_" または "/api/admin/*_" にマッチ
                            └─ SukhiFedi.Web.PluginPlug
                               └─ :rpc.call(api@api, SukhiApi.Router, :handle, [req])
                                                │
                                                ▼
                                        api BEAMノード (node api@api)
                                        SukhiApi.Registry（自動発見）
                                          └─ Capabilities.MastodonInstance
                                          └─ Capabilities.<他にも…>       ← 1ファイル = 1機能
```

**リクエスト / レスポンス契約**（`SukhiApi.Capability` moduledoc 参照）:

```
req  :: %{method: "GET" | "POST" | …, path: "/api/v1/…",
          query: "a=1&b=2", headers: [{k, v}], body: binary}
resp :: %{status: 200, body: iodata, headers: [{k, v}]}
```

**エンドポイント追加の手順** — `api/lib/sukhi_api/capabilities/` に
ファイルを置くだけ:

```elixir
defmodule SukhiApi.Capabilities.InstancePeers do
  use SukhiApi.Capability, addon: :mastodon_api  # コアなら省略

  @impl true
  def routes, do: [{:get, "/api/v1/instance/peers", &peers/1}]

  def peers(_req), do: {:ok, %{status: 200, body: "[]",
                               headers: [{"content-type", "application/json"}]}}
end
```

以上、ぜんぶ。ルータ編集もマニフェスト更新もいらない。
`use SukhiApi.Capability` マクロがモジュール属性を永続化して、
`SukhiApi.Registry` が実行時に
`:application.get_key(:sukhi_api, :modules)` をスキャンして拾う。

**失敗モード**:

- `plugin_nodes` 未設定 → 503 `{"error":"plugin_unavailable"}`
- `:rpc` 時にノード到達不能 → 503 `{"error":"plugin_rpc_failed"}`
- リモートノード側でハンドラがクラッシュ → 向こうで catch して 500
- どのcapabilityにも該当しないパス → 向こうで 404

## 9. 可観測性（OpenTelemetryなし）

- **メトリクス**: `PromEx` が4000番ポートで `/metrics` 公開。外部の
  scraper（セルフホストPrometheus、Grafana Cloud Free、等々）が
  引きに来る。最初から Ecto / Oban / Plug / BEAM system メトリクスが
  揃ってる。独自メトリクスは `:telemetry.execute` +
  `telemetry_metrics`。
- **ダッシュボード**: レポジトリには入れない。ローカルか managed の
  Grafanaを `http://<host>:4000/metrics` を食べてるPrometheusに
  向けてね。
- **トレース**: **あえて入れてない**。OpenTelemetry / Jaeger / otelcol を
  却下した理由は (a) Fedify側のOTel統合が重い、(b) 私たちの規模だと
  運用コストが割に合わない、(c) `request_id` 付きの構造化ログで
  「道を辿り直す」用途はカバーできる。`elixir/mix.exs` に
  `opentelemetry_*` 依存がゼロなのは確信犯。
- **構造化ログ**: 各コントローラ/ワーカーは `Logger.metadata(request_id: …)`
  を付ける。あとで `grep` でインシデントを再現できるから。

機能追加のたびに出していくカスタムメトリクス:

| メトリクス                          | 種類      | 出す場所             |
| ----------------------------------- | --------- | -------------------- |
| `sukhi_outbox_pending_count`        | gauge     | `Outbox.Relay` tick  |
| `sukhi_outbox_publish_rate`         | counter   | `Outbox.Relay`       |
| `sukhi_delivery_success_rate`       | counter   | `Delivery.Worker`    |
| `sukhi_delivery_failure_rate`       | counter   | `Delivery.Worker`    |
| `sukhi_fedify_latency_ms`           | histogram | `FedifyClient`       |
| `sukhi_inbox_request_rate`          | counter   | `InboxController`    |
| `sukhi_delivery_pool_utilization`   | gauge     | Finch telemetry      |

## 10. 環境変数

| 変数                                 | サービス    | デフォルト                | 用途                                |
| ------------------------------------ | ----------- | ------------------------- | ----------------------------------- |
| `DB_HOST` / `USER` / `PASS` / `NAME` | Elixir      | （本番では必須）          | Postgres接続                        |
| `DB_POOL_SIZE`                       | Elixir      | `10`                      | Ectoプールサイズ                    |
| `NATS_HOST` / `NATS_PORT`            | Elixir      | `127.0.0.1:4222`          | NATSクライアント                    |
| `NATS_URL`                           | Bun         | `nats://localhost:4222`   | NATSクライアント                    |
| `PLUGIN_NODES`                       | Elixir      | `api@api` (compose)       | `:rpc` 対象ノード（空白・カンマ区切り） |
| `RELEASE_COOKIE`                     | Elixir+api  | `sukhi_fedi_dev_cookie`   | 分散Erlang共有シークレット          |
| `DOMAIN` / `INSTANCE_TITLE`          | api         | `localhost:4000` / `sukhi-fedi` | NodeInfo / WebFinger の出力 |
| `ENABLED_ADDONS` / `DISABLE_ADDONS`  | 全部        | `all` / `""`              | カンマ区切りのアドオンid            |

## 11. ローカルで動かす

### 開発用スタック
```bash
docker-compose up -d   # postgres + nats + nats-bootstrap + gateway + bun + api + watchtower
# http://localhost:4000             — Elixir ゲートウェイ
# http://localhost:4000/metrics     — PromEx（外からスクレイプしてね）
```

### テスト用スタック（密閉、ポートを分けてある）
```bash
docker-compose -f docker-compose.test.yml up -d
# Postgres : localhost:15432   (db: sukhi_fedi_test, tmpfs なので毎回まっさら)
# NATS     : localhost:14222   (monitor: :18222)
# fedify-service : NATS Micro キュー "fedify-workers"
```

### テスト実行

```bash
# Elixirユニットテスト（密閉、ライブ依存なし）:
cd elixir && mix test --no-start

# Elixir統合テスト（docker-compose.test.yml 起動済みで）:
cd elixir && mix test --only integration

# Bun テスト:
cd bun && bun test

# Bun 全体の型チェック（TS 6.0.3 を tsc 経由で）:
cd bun && bun run check
```

## 12. 水平スケールの姿勢

- ElixirもBunも **ステートレス**設計 — 状態は全部PostgresかNATSに。
  `mix release` + `docker compose up --scale gateway=N` でゲートウェイ
  複製が増える。Bunコンテナを複製すると NATS Micro のキューグループ
  `fedify-workers` で自動ロードバランス。
- `Outbox.Relay` の `FOR UPDATE SKIP LOCKED` のおかげで複数リレーを
  同時に走らせても安全（各自が別のバッチを取る）。
- ETSキャッシュ（WebFinger JRD、リモートactor fetch、Bunのimport済み
  CryptoKey）は **ノードローカル**。ミスしたらPostgresかHTTP fetchに
  フォールバックするから、ノード間でキャッシュがズレても壊れない。
- 将来の `SUKHI_ROLE=inbox|api|worker|all` スイッチが入ると、
  同じイメージのまま起動するサブツリーを切り替えられる。例えば
  DoS時に inbox受付だけを専用ノードに逃がせる、みたいな使い方。

## 13. リファクタの哲学（strangler-fig）

コードベースはずっと小さな、常にマージ可能な段階を積み重ねて
今の形になってる。各段階で `mix test` と `bun test` を緑に保って、
独立してリリースできた。

```
0   足場づくり                ✅ 完了
1   Outbox インフラ           ✅ 完了
2   NATS Micro（追加のみ）    ✅ 完了
2-b 古い ap.* の除去          ✅ FedifyClient範囲は完了；ap.verify/inbox は残存
3   HTTP統合                  ✅ WebFinger / NodeInfo / ActorFetcher / RateLimitPlug
3-b Bun HTTP の除去           ✅ bun/lib/ 削除（Honoサーバーなし）、bun/api/ ハンドラ削除
3-c プラグインAPI (api/)      ✅ 分散Erlangのプラグインノード、capability自動登録
4   配信をElixirに            ✅ Worker が FedifyClient + delivery_receipts を使用
4-b Finchプール + E2E        ✅ Finchプール 50×4 per host
5   神モジュール分割          ✅ db_nats_listener 617 → 80行のディスパッチャ + 5 Nats.* モジュール
6   docs + デッドコード掃除   ✅ 古いdocs削除、README / ARCHITECTUREが揃ってる
7   ホットパス最適化          ✅ FanOut事前計算、Oban.insert_all、
                                 Outbox.Relay のバルク update_all、
                                 outbox部分インデックス、STATEMENTトリガー、
                                 notes / follows インデックス、
                                 Bun CryptoKeyキャッシュ
```

機能を追加するときは、まず自分がどのステージに属するのか、
そのステージの完了を待った方がいいのか考えるんだよー。

---

*この日本語版は [`ARCHITECTURE.md`](ARCHITECTURE.md) の翻訳。
内容がズレたら英語側を正とするね。*
