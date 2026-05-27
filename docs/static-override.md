# 静的ファイルの即時差し替え

CSS や SPA の小さな修正のたびに CI ビルド + image push + accessory
reboot(計 3-5 分)を待つのは辛いので、gateway 側に host 由来の
override dir を一枚かぶせている。仕組みは単純:

```
gateway container
  ├── /app/priv/static/          ← image にビルド時に焼き込まれたもの
  └── /app/priv/static-override/ ← ホストの /var/lib/sukhi-fedi/static を read-only bind
```

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
