# このファイルはオーディエンスと検索語を手で登録する rake タスク（動作確認用）。
# AIでの検索語生成は後の app/services/query_generator.rb で作るので、ここは仮の検索語を入れるだけ。
namespace :seed do
  desc "動作確認用に「Web制作を頼む人」と仮の検索語3つを登録する"
  task web_seisaku: :environment do
    audience = Audience.find_or_create_by!(slug: "web-seisaku") do |a|
      a.name = "Web制作を頼む人"
      a.description = "自社サイトやLPの制作・改善を外注したい小さな会社・個人事業主"
    end
    puts "オーディエンス: #{audience.slug} / #{audience.name}"

    queries = [
      "ホームページ 制作 依頼",
      "ホームページ 問い合わせ 来ない",
      "web制作 外注 失敗"
    ]

    queries.each do |query|
      audience_query = audience.audience_queries.find_or_create_by!(source: "youtube", query: query) do |q|
        q.generated_by = "human"
        q.is_active = true
      end
      puts "  検索語: #{audience_query.query}（#{audience_query.generated_by}）"
    end
  end
end
