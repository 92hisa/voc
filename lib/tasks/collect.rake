# このファイルは収集をコマンドから動かすための rake タスク。
# 例: bin/rails collect[web-seisaku,youtube,7]
desc "投稿を収集する collect[slug,source,days]"
task :collect, [ :slug, :source, :days ] => :environment do |_task, args|
  slug = args[:slug] or abort "使い方: bin/rails collect[web-seisaku,youtube,7]"
  source = args[:source] || "youtube"
  days = (args[:days] || 7).to_i

  # 収集の進み具合を画面にも出す。SQLまで出ると読めないので info 以上だけ、本文はそのまま
  console = ActiveSupport::Logger.new($stdout, level: :info)
  console.formatter = ->(_severity, _time, _progname, message) { "#{message}\n" }
  Rails.logger.broadcast_to(console)

  result = CollectJob.perform_now(slug, source, days)

  puts
  puts "── 収集結果 #{slug} / #{source} / 直近#{days}日 ──"
  puts "検索語        : #{result.query_count}件"
  case source
  when "youtube"
    puts "見た動画      : #{result.video_count}本"
  when "bluesky"
    puts "取得した投稿  : #{result.fetched_count}件"
  end
  puts "保存した投稿  : #{result.saved_count}件"
  puts "捨てた投稿    : #{result.skipped_count}件（短い・日本語でない・既に保存済み）"
  if source == "youtube"
    puts "使用クォータ  : #{result.quota_used} / #{Sources::YoutubeSource::DAILY_QUOTA_LIMIT} ユニット"
    puts "クォータ中断  : #{result.stopped_by_quota ? 'あり' : 'なし'}"
  end
  puts "posts 合計    : #{Audience.find_by!(slug: slug).posts.for_source(source).count}件"
end
