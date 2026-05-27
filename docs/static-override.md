# 静的ファイルの即時差し替え

CSS や SPA の小さな修正のたびに CI ビルド + image push + accessory
reboot(計 3-5 分)を待つのは辛いので、gateway 側に host 由来の
override dir を一枚かぶせている。仕組みは単純:

```
gateway container
  ├── /app/lib/sukhi_fedi-<vsn>/priv/static/   ← image にビルド時に焼き込まれたもの
  └── /app/priv/static-override/               ← ホストの /var/lib/sukhi-fedi/static を read-only bind
```

baked path は `:code.priv_dir/1` が release version 込みで返すので、
override は version に依らない固定パスにして deploy.yml を毎回直さ
ずに済むようにしている(`STATIC_OVERRIDE_DIR` 環境変数で上書きも
可能)。

`SukhiFedi.Web.Router.serve_static/2` は **override を先に見て、無ければ
baked を返す**。だから:

- override を空にしておけば、image 単体で完結する(初回 deploy の安心)
- override に CSS を 1 個置けば、その path だけ即時で差し替わる
- override を消せば、baked-in に戻る

## ローカルから差し替える

`Makefile` に二つ target がある:

```sh
# SPA まるごと(npm run build → rsync)
make push-static

# CSS だけ(src/styles/*.css → host:/styles/)
make push-styles
```

どちらも `scp/rsync` でファイルを置くだけ。BEAM の reload は不要 ─
`File.read!` のキャッシュは無いので、次の HTTP リクエストから新しい
内容が返る。

接続先を変えるなら env で:

```sh
DEPLOY_HOST=192.0.2.10 DEPLOY_USER=ubuntu make push-styles
```

## ホスト側の初回セットアップ

初回だけ host に dir を作る必要がある(`make push-static` が自動でやる
が、手作業なら):

```sh
ssh rocky@host 'sudo mkdir -p /var/lib/sukhi-fedi/static && sudo chown rocky /var/lib/sukhi-fedi/static'
```

deploy.yml の `accessories.gateway.options.volume` がこの host path を
bind しているので、accessory boot 時に自動でマウントされる。

## いつ使わないか

- `mix.exs` や `.ex` ファイルを触ったら、これでは反映されない
  ─ image rebuild + `kamal accessory reboot gateway` が必要
- `priv/repo/migrations/` を増やしたら同じく reboot 必要
- `botPolicies.yaml` や `imprint.md` は anubis image に焼かれている
  ので、Anubis 側で同じ override 機構を作るか、image rebuild

## 安全のために

- override mount は `:ro` で読み取り専用 ─ コンテナ内のバグで上書き
  されない
- `serve_static/2` の path-traversal guard はそのまま生きる ─ override
  でも `..` は弾く

## 抜け穴(やらかしやすい二つ)

### 1. SPA の CSS は `/static/styles/` 経由では更新できない

SPA は Vite が CSS を bundle して `_app/immutable/assets/<hash>.css`
を吐く。`+layout.svelte` の `import '../styles/app.css'` はビルド時に
そっちへ食われる。だから `web/src/styles/app.css` を `push-styles`
で投げても、SPA のページ(timeline / signup / check)には反映されない。

`/static/styles/app.css` を読むのは **server-rendered な /login と
/oauth/authorize の consent 画面だけ**。SPA 側のスタイルを直したい
ときは `make push-static`(`npm run build` + rsync 一式)が必要。

### 2. `rsync --delete` が `styles/` を吹き飛ばす

`web/build/` の出力に `styles/` は含まれない(あれは別管理)。
だから素朴に `rsync -av --delete web/build/ host:STATIC_DIR/` を
やると、host 側の `styles/` まで削られて /login が裸 HTML になる。

Makefile の `push-static` は `--exclude=styles` を付けてこれを
避けている。手で rsync するときも同じ exclude を忘れない。
