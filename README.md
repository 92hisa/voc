# お客さんの声リサーチ

Threads・YouTube・Bluesky上の「お客さんの声」を集め、5つのレンズ（悩み／探している／お金の話／乗り換え／話題）に
分類して、週次でメールとWebで届けるサービス。企画の詳細は `docs/企画書_v0.4.md`、開発ルールは `CLAUDE.md`。

## 必要なもの

- Ruby 3.3.6（`.ruby-version` のとおり。rbenv などで入れる）
- SQLite3（macOS なら最初から入っている）
- Node.js は不要（Tailwind は `tailwindcss-rails` が専用バイナリを使う）

## セットアップ

```bash
bundle install          # gem を入れる
cp .env.example .env    # APIキーなどを書く（.env はコミットしない）
bin/rails db:prepare    # SQLite のDBを作ってマイグレーション
```

## 起動

```bash
bin/dev                 # Railsサーバ + Tailwindの監視ビルドを同時に起動
```

→ http://localhost:3000

`bin/dev` は `Procfile.dev` の2つのプロセス（`web` と `css`）をまとめて動かす。
Tailwind のCSSを1回だけビルドしたいときは `bin/rails tailwindcss:build`。

## テスト

```bash
bin/rails test          # Minitest。1タスク終えるごとにこれを通す
```

## 検索語（AI生成）

```bash
bin/rails seed:audiences                  # 初期3オーディエンスを登録（検索語は入らない）
bin/rails queries:generate                # 全オーディエンスの検索語をAIで生成
bin/rails queries:generate[web-seisaku]   # 1オーディエンスだけ作り直す
```

`app/services/query_generator.rb` が `name` と `description` から媒体別に検索語を10〜15個作り、
`audience_queries` に `generated_by=ai` で保存する。方針（頼む側の言葉を使う・売り手の語彙は避ける）は
同ファイルの `SYSTEM_PROMPT` にある。**作り直すと、その媒体の既存の検索語は `is_active=false` になる。**
生成結果は理由つきで `docs/eval/queries.md` に出力されるので、収集前にここで良し悪しを見る。

## 収集（YouTube）

```bash
bin/rails collect[web-seisaku,youtube,7]  # 直近7日の動画のコメントを集めて posts に保存
```

`app/services/sources/youtube_source.rb` が `audience_queries` の検索語ごとに
`search.list`（100ユニット）→ `commentThreads.list`（1ページ1ユニット）を**直列**で呼ぶ。
使ったクォータは実行中のログと最後のまとめに出て、1日の上限1万ユニットに届く前に途中で止まる。
1回の実行の目安は「検索語の数 × 100 ＋ 見た動画の数」ユニット（検索語15個なら約1,600）。

保存するのはコメントID・本文・日時・公開指標（`metrics` の `like_count` / `reply_count`）・動画IDだけ。
**投稿者名・チャンネル名は保存しない。** 本文は30日で失効（`expires_at`）し、以降は集計値だけを残す。
同じコメントは2回目以降スキップするので、途中で失敗しても同じコマンドで再開できる。

どの検索語がどのチャンネルの動画を拾ったかは実行ログに出る（保存はしない）。
検索語の見直しに使う。1回の取りすぎを防ぐ上限は `YoutubeSource` の定数（検索語ごと10本／動画ごと5ページ＝最大500件）。
1日に何度も回すときは `quota_limit` を分けて渡す。

## 収集（Bluesky）

```bash
bin/rails collect[web-seisaku,bluesky,7]  # 直近7日の投稿を集めて posts に保存
```

`app/services/sources/bluesky_source.rb` が Faraday で AT Protocol のXRPCを直接叩く。
`com.atproto.server.createSession`（ハンドル＋アプリパスワード）でログインし、
`app.bsky.feed.searchPosts` を `lang=ja` / `sort=latest` / `since=直近N日` でページングする。クォータはない。

保存するのは投稿URI・本文・日時・公開指標（`like_count` / `reply_count` / `repost_count` / `quote_count`）だけ。
**表示名・アバター・プロフィールは保存しない**（投稿URIにDIDが入るが、これは投稿IDそのもの）。
本文は30日で失効（`expires_at`）。同じ投稿は2回目以降スキップするので再実行できる。

検索は**書いた語を全部含む投稿しか返らない**ので、検索語は1〜2語にする（3語以上はほぼ0件）。
逆に「サイト」のような広い1語はレシピサイト・同人サイトの話に当たるので、主題語は具体的にする。

## データベース

SQLite。開発用のファイルは `storage/development.sqlite3`。
本番（Render）は環境変数 `DATABASE_PATH`（例 `/data/production.sqlite3`）で永続ディスク上を指す。
キャッシュ用（Solid Cache）とジョブ用（Solid Queue）のDBは、同じフォルダに自動で並べて作られる。

主なテーブル（詳しくは `CLAUDE.md` 第5節と `db/schema.rb`）:

| テーブル | 役割 |
|---|---|
| `audiences` | 誰の声を集めるか。`slug` がURLとタスク引数になる |
| `audience_queries` | 媒体ごとの検索語（AI生成 or 人手） |
| `posts` | 収集した投稿。`(source, external_id)` が一意。投稿者の氏名・アイコンは保存しない |
| `classifications` | AI分類の結果（lens / side / intent）。1投稿につき1件で、分類し直すと上書き |
| `clusters` / `cluster_posts` | 週ごと・レンズごとに似た投稿をまとめたもの |
| `weekly_snapshots` | 週次の集計（件数・前週比・狙い目スコア）。**削除しない** |
| `subscribers` | 週次メールの購読者。オーディエンスごとに1メールアドレス1件 |

## 環境変数

`.env.example` を参照（`ANTHROPIC_API_KEY` / `AI_MODEL` / `YOUTUBE_API_KEY` / `BLUESKY_HANDLE` /
`BLUESKY_APP_PASSWORD` / `RESEND_API_KEY` / `MAIL_FROM` / `APP_HOST` / `GA4_ID` / `META_PIXEL_ID` /
`DATABASE_PATH`）。開発中は `.env` に書けば `dotenv` が読み込む。本番は Render の環境変数に設定する。

## ジョブ（Solid Queue）

本番では Solid Queue がジョブを処理する（`bin/jobs` で起動、定期実行は `config/recurring.yml`）。
開発中の Active Job はプロセス内で非同期に動く設定のまま。週次バッチは後のステップで作る。

## これから作るもの

収集（YouTube・Bluesky）→ AI分類 → クラスタ化・週次集計 → 診断LP → 週次メール の順に作る。
手順は `CLAUDE.md` 第9節。
