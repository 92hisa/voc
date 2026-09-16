# このファイルは初期データ。`bin/rails db:seed` と `bin/rails seed:audiences` で流れる。
# 本番（Render）では、DBを新しく作ったときに db:prepare が自動で流す。
# 何度実行してもよい（同じ slug / 検索語があれば作り直さない）。
#
# threads の検索語は `bin/rails queries:generate[,threads]` がAIで作ったものを、
# 新しい環境でもすぐ画面が動くように書き写したもの。作り直すとこの内容は入れ替わる。
audiences = [
  {
    slug: "web-seisaku",
    name: "Web制作を頼む人",
    description: "自社サイトやLPの制作・改善を外注したい小さな会社・個人事業主",
    threads_queries: [
      "LP 作りたい", "サイト 直したい", "サイト制作 見積もり",
      "ネットショップ 作りたい", "フリーランス 制作 依頼", "ホームページ リニューアル",
      "ホームページ 予算", "ホームページ 作りたい", "ホームページ 反応ない",
      "ホームページ 古い", "ホームページ 更新できない", "ホームページ 見積もり",
      "ホームページ 頼みたい", "制作会社 選び方",
    ]
  },
  {
    slug: "ec-unei",
    name: "EC運営で困っている人",
    description: "ネットショップ（自社EC・楽天・Amazonなど）の売上や日々の運用で困っている事業者",
    threads_queries: [
      "Amazon 出品 大変", "Amazon 手数料 高い", "EC 売上 伸びない",
      "EC 外注したい", "カート 離脱 多い", "ネットショップ アクセス 増えない",
      "ネットショップ リピーター 増えない", "ネットショップ 作りたい", "ネットショップ 売れない",
      "ネットショップ 運営 大変", "受注管理 大変", "在庫管理 大変",
      "楽天 売上 落ちた", "楽天 広告 高い", "発送業務 大変",
    ]
  },
  {
    slug: "gyomu-jidoka",
    name: "業務自動化・ツール導入を検討している人",
    description: "手作業や属人化した業務を、ツール導入や自動化で楽にしたい小さな会社・個人事業主",
    threads_queries: [
      "エクセル 面倒", "シフト管理 面倒", "スプレッドシート 限界",
      "ツール導入 検討", "予約管理 面倒", "人手不足 効率化",
      "在庫管理 大変", "属人化 困る", "手作業 大変",
      "業務 楽にしたい", "業務効率化 したい", "業務改善 したい",
      "経理 手間", "自動化 したい", "請求書 手作業",
    ]
  },
].freeze

audiences.each do |attributes|
  audience = Audience.find_or_initialize_by(slug: attributes[:slug])
  audience.update!(name: attributes[:name], description: attributes[:description])

  attributes[:threads_queries].each do |query|
    audience_query = audience.audience_queries.find_or_initialize_by(source: "threads", query: query)
    audience_query.generated_by = "ai" if audience_query.new_record?
    audience_query.is_active = true
    audience_query.save!
  end

  puts "#{audience.slug} / #{audience.name}（threads の検索語 #{attributes[:threads_queries].size}件）"
end
