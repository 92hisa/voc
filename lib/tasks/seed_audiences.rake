# このファイルは初期データを流す rake タスク。中身は db/seeds.rb にある（本番の db:prepare と同じもの）。
namespace :seed do
  desc "初期3オーディエンスとThreadsの検索語を登録する（db/seeds.rb を流す）"
  task audiences: :environment do
    Rails.application.load_seed
  end
end
