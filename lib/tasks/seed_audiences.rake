# このファイルは初期オーディエンスを登録する rake タスク。
# 検索語は入れない（AIで作る → bin/rails queries:generate）。
namespace :seed do
  AUDIENCES = [
    {
      slug: "web-seisaku",
      name: "Web制作を頼む人",
      description: "自社サイトやLPの制作・改善を外注したい小さな会社・個人事業主"
    },
    {
      slug: "ec-unei",
      name: "EC運営で困っている人",
      description: "ネットショップ（自社EC・楽天・Amazonなど）の売上や日々の運用で困っている事業者"
    },
    {
      slug: "gyomu-jidoka",
      name: "業務自動化・ツール導入を検討している人",
      description: "手作業や属人化した業務を、ツール導入や自動化で楽にしたい小さな会社・個人事業主"
    }
  ].freeze

  desc "初期3オーディエンスを登録する"
  task audiences: :environment do
    AUDIENCES.each do |attributes|
      audience = Audience.find_or_initialize_by(slug: attributes[:slug])
      audience.update!(name: attributes[:name], description: attributes[:description])
      puts "#{audience.slug} / #{audience.name}"
    end
    puts "検索語はまだ入っていません。bin/rails queries:generate で作ります。"
  end
end
