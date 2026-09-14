# CLAUDE.md — お客さんの声リサーチ（Ruby on Rails版）

このファイルはClaude Codeが毎回読む前提の指示書。企画の詳細は `docs/企画書_v0.4.md`。
開発者は1人（副業）。Rubyは読めるがRailsは初心者。**コードは読んで理解できる書き方を優先し、魔法は避ける。**

## 1. このプロジェクトは何か

自分で集客している小さな会社・個人事業主向けに、Threads・YouTube・Bluesky上の「お客さんの声」を集め、
5つのレンズ（悩み／探している／お金の話／乗り換え／話題）に分類して、週次でメールとWebで届けるサービス。
営業・ヒアリング・個人名での発信はしない。完全セルフサーブ。

### 今のフェーズで作るもの
1. 収集（YouTube・Bluesky。Threadsは審査通過後）
2. AI分類・クラスタ化（購入者側の投稿だけを集計）
3. 週次スナップショット（件数・前週比・狙い目）
4. 無料診断LP（オーディエンス選択→結果画像→シェア→メール登録）
5. 週次メール（今週の悩みトップ3）

### 今のフェーズで作らないもの
ログイン後の画面、決済（Stripe Payment Linksで後付け）、LINE配信、リード即時通知（Pro）、ペルソナ生成、Threads（審査待ち）

## 2. 技術構成（変更しない）

| | |
|---|---|
| 言語・FW | Ruby 3.3 / Rails 8 |
| DB | SQLite（本番も。Rails 8の標準構成） |
| ジョブ | Solid Queue（Rails 8標準）。週次は `config/recurring.yml` |
| 画面 | ERB＋Turbo＋Tailwind（`tailwindcss-rails`）。JSは最小 |
| AI | `anthropic` gem（公式）。モデルは `AI_MODEL` |
| メール | Action Mailer＋Resend（`resend` gem） |
| 画像 | `ruby-vips`（OG画像・シェア画像） |
| 外部API | YouTube：`google-apis-youtube_v3` gem。Bluesky：`Faraday` でAT Protocol直叩き（薄いクライアントを自作） |
| ホスティング | Render（Web＋ジョブを同一サービス、永続ディスク `/data`）。GitHub pushで自動デプロイ |
| 計測 | GA4、Meta Pixel |
| テスト | Minitest（Rails標準） |

## 3. 絶対に守ること

- **公式APIのみ。** スクレイピング、非公式ライブラリ、HTMLの直接取得は禁止。知恵袋・5ch・Instagram・X・Googleマップ・食べログ・Amazonは触らない
- **外部APIの呼び出しは `app/services/sources/` 配下に1媒体1クラスで閉じる。** 他の場所で `Google::Apis` や Bluesky のエンドポイントを直接触らない
- **YouTubeは集計専用。** コメント投稿者を個人として追跡・スコア化・表示しない
- **投稿者の氏名・アイコン・プロフィールを保存・表示しない。** 保存は投稿ID・本文・日時・媒体・公開指標のみ
- **自動返信・自動DM・リストのエクスポート機能は作らない**
- 生投稿の本文は各媒体の規約で許される期間だけ保持（`expires_at`）。集計値は永続
- 取得は直列。失敗したらDBに書く前に例外で落とす。途中再開できるように処理単位を小さく
- 秘密情報は `rails credentials` か環境変数。コミットしない
- センシティブな業種（健康・宗教・金銭・在留資格）のオーディエンスは作らない
- Railsの規約に従い、独自の抽象化を足さない。1ファイルを読めば何をしているか分かる粒度

## 4. ディレクトリ（Rails標準＋以下）

```
app/models/            audience, audience_query, post, classification, cluster, weekly_snapshot, subscriber
app/services/sources/  youtube_source.rb, bluesky_source.rb, threads_source.rb（後）
app/services/          query_generator.rb（検索語生成）, classifier.rb（分類）, clusterer.rb, snapshot_builder.rb,
                       spike_detector.rb（反応数の急増）, og_image_renderer.rb
app/jobs/              collect_job, classify_job, cluster_job, snapshot_job, render_job, weekly_job
app/controllers/       diagnosis_controller（LP）, subscribers_controller, og_controller
app/mailers/           weekly_mailer
app/views/diagnosis/   index, show（結果）
lib/tasks/             eval.rake（人手評価CSV）, seed_audiences.rake
docs/                  企画書、規約確認表、eval/、runs/
```

## 5. データ構造

すべての収集データに「オーディエンス・レンズ・クラスタID・週」を付ける。時系列は後付けできない。

```
audiences         slug, name, description
audience_queries  audience_id, source, query, is_active, generated_by(ai|human)
posts             audience_id, source, external_id, text, posted_at, metrics(json),
                  video_id, fetched_at, expires_at   UNIQUE(source, external_id)
classifications   post_id, lens, side, intent, confidence, model, classified_at
                  lens: pain|seeking|money|switching|trending|noise
                  side: buyer|seller|peer|unknown   intent: now|vague|none
clusters          audience_id, lens, week_start, name, representative_text
cluster_posts     cluster_id, post_id
weekly_snapshots  audience_id, week_start, lens, cluster_id,
                  post_count, author_count, wow_change, supply_count, opportunity_score
                  （削除しない。これがデータ資産）
subscribers       email, audience_id, confirmed_at, unsubscribed_at, utm(json)
```

- 集計は `side=buyer` のみ。seller/peer は分類まで
- `opportunity_score` = 悩み投稿数 ÷ 同テーマの `side=seller` 投稿数（supply_count）

## 6. 5つのレンズ（分類プロンプトの基準）

| lens | 拾う投稿 | 例 |
|---|---|---|
| pain | 困っている・分からない・失敗した | 「ホームページ作ったけど問い合わせゼロ」 |
| seeking | 誰か頼める人・おすすめ・比較して | 「Web制作で信頼できる人いませんか」 |
| money | 高い・いくらかかる・払う価値 | 「見積もり50万って普通？」 |
| switching | やめた・別のに変えたい | 「制作会社やめてフリーランスに頼んだ」 |
| trending | 反応が多い・伸びている | spike_detector が検出 |
| noise | 宣伝、同業者の営業投稿、無関係 | — |

`side` は「買う側／売る側／同業者」。売り手の宣伝を buyer に入れない。

## 7. 開発の進め方

- 1タスク1コミット。動くものを小さく。各ステップの最後に `bin/rails test` を通す
- 分類の精度は `bin/rails eval:export` で `docs/eval/` にCSV（post_id, text, ai_lens, ai_side, human_lens, human_side）を出し、人手で埋めて `bin/rails eval:score` で適合率を出す。目標70%
- ジョブの実行ログは `docs/runs/` に残す
- 迷ったら企画書11章の合格条件に照らす。効かない作り込みはしない
- 説明は日本語で。ファイルの先頭に「このファイルは何をするか」を1〜2行コメントで書く

## 8. コマンド

```
bin/dev                                  # 開発サーバ
bin/rails seed:audiences                 # 初期3オーディエンス登録
bin/rails collect[web-seisaku,youtube,7] # 収集
bin/rails classify[web-seisaku]
bin/rails cluster[web-seisaku,2026-09-08]
bin/rails snapshot[web-seisaku,2026-09-08]
bin/rails render_og[web-seisaku]
bin/rails weekly[web-seisaku]            # 上を順に全部＋メール送信
bin/rails eval:export[web-seisaku,100]
bin/rails eval:score[web-seisaku]
```

---

## 9. Claude Codeに渡す指示（この順番で1つずつ）

### 指示1：土台
```
Rails 8 で新規アプリを作って（SQLite、Solid Queue、tailwindcss-rails、Minitest）。
第5節のモデルとマイグレーションを作成し、UNIQUE制約と外部キーを付ける。
.env.example に必要なキー名を列挙し、README に起動手順（日本語）。bin/dev で起動確認まで。
```

### 指示2：YouTube収集
```
app/services/sources/youtube_source.rb を作って。google-apis-youtube_v3 の利用はこのファイルだけ。
1) audience_queries の query ごとに search.list（type=video, relevanceLanguage=ja, publishedAfter=直近N日）
2) 各動画の commentThreads.list（maxResults=100、ページング）
3) posts に保存（投稿者名・チャンネル名は保存しない。like_count は metrics に）
クォータを計算してログに出し、1日1万ユニットを超える前に止める。直列取得。
collect_job と rake タスク `collect[slug,source,days]` を作り、`bin/rails collect[web-seisaku,youtube,7]` で動くように。
```

### 指示3：Bluesky収集
```
app/services/sources/bluesky_source.rb を作って。Faraday で app.bsky.feed.searchPosts を叩く薄いクライアント。
認証は createSession（ハンドル＋アプリパスワード）。日本語投稿のみ posts に保存。表示名・アバターは保存しない。
```

### 指示4：検索語生成
```
app/services/query_generator.rb を作って。オーディエンスの name と description から anthropic gem で
媒体別に検索語を10〜15個生成し、audience_queries に generated_by=ai で保存。
seed:audiences で初期3オーディエンス（Web制作を頼む人／EC運営で困っている人／業務自動化・ツール導入を検討している人）を登録して実行。
生成結果を docs/eval/queries.md に出力。
```

### 指示5：分類
```
app/services/classifier.rb を作って。posts を anthropic gem で分類し classifications に保存。
出力は JSON（lens, side, intent, confidence, reason）。第6節の定義をシステムプロンプトに入れる。
20件ずつバッチ、再実行しても重複しない。lib/tasks/eval.rake で人手評価用CSVの出力（eval:export）と
適合率の計算（eval:score）を作る。まず「Web制作を頼む人」100件で回して。
```

### 指示6：クラスタ化・週次集計・急増検出
```
app/services/clusterer.rb と snapshot_builder.rb を作って。side=buyer の投稿をレンズごとに
埋め込み（anthropic gem か簡易なTF-IDF＋コサイン。まずは簡易でよい）で近い順にまとめ、
anthropic gem でクラスタ名と代表表現を付ける。weekly_snapshots に post_count, author_count, wow_change,
supply_count, opportunity_score を保存。
spike_detector.rb は、反応数（いいね・返信）の直近分布からの外れ値を検出し lens=trending を付ける。
```

### 指示7：診断LP
```
diagnosis_controller と views を作って。3画面：
1) / オーディエンス選択（初期3つ）
2) /d/:slug weekly_snapshots から lens=pain の上位3クラスタを「今週の悩みトップ3」としてカード表示（件数・前週比）。
   同じカードを /og/:slug.png として ruby-vips で生成し OGP に設定。「Threadsに投稿する」ボタンでシェア
3) /subscribe メール登録（subscribers に保存、Resend で確認メール、UTM保持）
計測：GA4 と Meta Pixel。イベント select_audience / view_result / click_share / submit_email。
デザインは余白広め、数字を大きく、装飾は最小。
```

### 指示8：週次メールとジョブ
```
weekly_mailer を作って「今週の悩みトップ3」（クラスタ名・件数・前週比・代表表現1つ）を送る。
weekly_job（collect→classify→cluster→snapshot→render→mail）を作り、config/recurring.yml で月曜08:00 JST に登録。
実行ログを docs/runs/ に残し、途中失敗から再開できるように。
render.yaml と環境変数一覧（ANTHROPIC_API_KEY / AI_MODEL / YOUTUBE_API_KEY / BLUESKY_HANDLE / BLUESKY_APP_PASSWORD /
RESEND_API_KEY / GA4_ID / META_PIXEL_ID / DATABASE_PATH=/data/production.sqlite3）を README に。
```
