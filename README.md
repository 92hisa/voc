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
