# NodeInfo watcher — 修正メモ

> **Status**: fixed in commit `cd6a5da` (2026-04-24). This doc is kept
> as a historical record of the diagnosis + chosen approach.
>
> 2026-04-23 時点の診断結果。hackers.pub のアップデートで watcher bot が
> 静かだった件を追い、2 つのバグと 2 つの改善点をまとめたメモ。

## TL;DR

pipeline が先頭から末端まで壊れてて、`nodeinfo_snapshots` に 1 件も
記録が残ってない。account 10 個だけが幽霊のように残ってる状態：

- `accounts` に `watcher-*` が 10 件（`monitored_domain` 埋まってる）
- `monitored_instances` は **空**
- `nodeinfo_snapshots` は **空**
- `oban_jobs` は **空**（PollCoordinator cron が一度も発火していない）
- `oban_peers` の leader は `sukhi_delivery@delivery`

## バグ 1 — 登録で monitored_instance が作られない

**場所**: `elixir/lib/sukhi_fedi/web/viewer_controller.ex:51`

```elixir
{:ok, result} = SukhiFedi.Release.seed_watcher(domain)
```

`Release.seed_watcher/1` → `seed_actor/2`（`release.ex:65-107`）は
`accounts` にしか insert しない。`NodeinfoMonitor.register/1` にある
`Ecto.Multi`（account + monitored_instance を原子的に作る
`nodeinfo_monitor.ex:26-59`）を経由しないといけない。

**直し方（案）**:
`register_watcher/2` の seed 呼び出しを `NodeinfoMonitor.register/1` に
切り替える。`register/1` を「`account` が既にあったら
`monitored_instance` だけ作る」形に緩めて冪等にする（今は
`Ecto.Multi.insert(:account, ...)` で unique 違反になる）。あるいは
`seed_watcher` に `MonitoredInstance` insert を足す——どちらでもいいが、
`NodeinfoMonitor` にまとめた方が register ロジックの真実が 1 箇所になる。

**バックフィル**:
既存 10 件の watcher account に対して `monitored_instances` 行を作る
SQL を 1 回だけ流す。

```sql
INSERT INTO monitored_instances (domain, actor_id, inserted_at, updated_at)
SELECT monitored_domain, id, NOW(), NOW()
FROM accounts
WHERE monitored_domain IS NOT NULL
ON CONFLICT (domain) DO NOTHING;
```

## バグ 2 — Oban cron が永遠に発火しない

**原因**: gateway（`elixir/`）と delivery（`delivery/`）が同じ DB で
同じ `Oban` 名前空間を共有 → `oban_peers` でリーダー選挙 → delivery が
4 秒先に起動して勝ってる。`Cron` plugin は **リーダーの側でしか動かない**。

- gateway の Oban config（`elixir/config/config.exs:12-22`）に cron あり
- delivery の Oban config（`delivery/config/config.exs:12-15`）には cron なし
- リーダー = delivery → cron plugin は存在しないまま
- gateway 側の cron 定義は誰にも実行されない

**直し方（案）**:
gateway の Oban インスタンスに独立した `:name` を付ける：

```elixir
# elixir/lib/sukhi_fedi/application.ex:25
{Oban, [name: SukhiFedi.Oban] ++ Application.fetch_env!(:sukhi_fedi, Oban)}
```

併せて `PollCoordinator`/`PollWorker` と gateway 側の全 `Oban.insert` に
`name: SukhiFedi.Oban` を渡す（`poll_coordinator.ex:32`,
`ap/instructions.ex:44,126`, `inbox_controller.ex:95`）。delivery 側は
`SukhiDelivery.Oban` として同様に分離しておくと将来事故らない。

## 改善 1 — 監視周期を 10 分に

**場所**: `elixir/config/config.exs:19`

```elixir
# before
{"0 * * * *", SukhiFedi.Addons.NodeinfoMonitor.PollCoordinator}
# after
{"*/10 * * * *", SukhiFedi.Addons.NodeinfoMonitor.PollCoordinator}
```

関連定数も調整：
- `poll_coordinator.ex:19-20` `@default_max_age_seconds` / `@unique_period_seconds`
  は今 3000 秒（50 分）。10 分周期だと `500` 秒前後に下げるのが自然
- `poll_worker.ex` のタイムアウト（`@timeout_ms` 10 秒）はそのままで OK
- `record_failure/2` の `inactive_threshold` は今 168（= 168 時間＝1 週間）。
  10 分周期だと同じ 1 週間で `168 * 6 = 1008` 回になるので、ここは
  「**回数**ではなく**期間**で判定」にリファクタするか、`1008` に上げる

## 改善 2 — 登録時に「監視を始めました」を投稿

**要件**: register_watcher が成功したら、登録直後に観測したバージョンを
含めた Note をその watcher actor から投稿する。

**実装のかたち（案）**:

```elixir
# NodeinfoMonitor に publish_initial_note を足す
def publish_initial_note(%MonitoredInstance{} = mi, snapshot) do
  sw = snapshot[:software_name] || "unknown"
  ver = snapshot[:version] || "?"

  content =
    "\u{1F440} #{mi.domain} の監視を始めました\n" <>
    "software: #{sw}\n" <>
    "version: #{ver}"

  Notes.create_note(%{
    "account_id" => mi.actor_id,
    "content" => content,
    "visibility" => "public"
  })
end
```

`register_watcher/2`（修正後）の流れ：
1. `NodeinfoFetcher.fetch/1` で snapshot 取る（今もやってる）
2. `NodeinfoMonitor.register/1` で account + monitored_instance 作る（バグ 1 の修正）
3. `NodeinfoMonitor.record_snapshot/2` で snapshot を保存 → `:initial` が返る
4. `NodeinfoMonitor.publish_initial_note/2` で Note 投稿
5. Note は標準の Outbox → FanOut → Delivery で配送される

`detect_change(nil, _) → :initial` の分岐（`nodeinfo_monitor.ex:115`）は
既に存在するので、record_snapshot の戻り値を見て `:initial` のときだけ
initial note を投げる、というルーティングにしてもよい。

## 確認手順（修正後）

1. 新規 domain を `/api/watchers` POST で登録
2. DB で `monitored_instances` と `nodeinfo_snapshots` 両方に行が
   できていること、`accounts.monitored_domain` と FK が繋がっていること
3. watcher actor のアウトボックスに「監視を始めました」ノートが出てる
4. 10 分後、`oban_jobs` に PollCoordinator → PollWorker の完了行が
   あり、`monitored_instances.last_polled_at` が更新されている
5. `raw` のダミー書き換えで `{:changed, _, _}` 経路が通り、
   「upgraded」ノートが出る

## 既存の 10 件アカウントの扱い

バックフィル SQL を流したあと、最初の poll cycle（10 分以内）で
全件 `:initial` として snapshot が埋まり、同時に「監視を始めました」
ノートが 10 件出る挙動になる。それでよければそのまま。嫌なら
`publish_initial_note` を「新規 register 経由のときだけ」呼ぶように
経路を分ける。
