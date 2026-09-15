# このファイルは検索語をAIで作る rake タスク。
# 例: bin/rails queries:generate          （全オーディエンス）
#     bin/rails queries:generate[web-seisaku]
namespace :queries do
  OUTPUT_PATH = Rails.root.join("docs/eval/queries.md")

  desc "検索語をAIで生成して audience_queries に保存する queries:generate[slug,source]"
  task :generate, [ :slug, :source ] => :environment do |_task, args|
    slug = args[:slug].presence
    sources = args[:source].presence ? [ args[:source] ] : QueryGenerator::SOURCES
    audiences = slug ? [ Audience.find_by!(slug: slug) ] : Audience.order(:id).to_a
    abort "オーディエンスがありません。bin/rails seed:audiences を先に実行してください。" if audiences.empty?

    # 生成の進み具合を画面にも出す
    console = ActiveSupport::Logger.new($stdout, level: :info)
    console.formatter = ->(_severity, _time, _progname, message) { "#{message}\n" }
    Rails.logger.broadcast_to(console)

    generated = audiences.map { |audience| [ audience, QueryGenerator.new(audience: audience).generate(sources: sources) ] }

    write_markdown(generated)
    puts
    puts "── 生成結果（#{OUTPUT_PATH.relative_path_from(Rails.root)} に出力）──"
    generated.each do |audience, results|
      results.each do |result|
        puts "#{audience.slug} / #{result.source}: 有効#{result.saved_count}件（旧#{result.deactivated_count}件を無効化）"
      end
    end
  end

  # 人が読んで検索語の良し悪しを確かめるための一覧。
  # いま有効な検索語をDBから書き出し、今回生成したぶんには理由も付ける（理由はDBに持たない）
  def write_markdown(generated)
    reasons = generated.flat_map { |_audience, results| results }
      .flat_map { |result| result.queries }
      .to_h { |item| [ item["query"], item["reason"] ] }

    lines = [ "# 検索語（いま有効なもの）", "" ]
    lines << "更新: #{Time.current.strftime('%Y-%m-%d %H:%M')}（生成モデル: #{ENV['AI_MODEL'].presence || QueryGenerator::DEFAULT_MODEL}）"
    lines << ""
    lines << "方針は媒体ごとに違う（`app/services/query_generator.rb` の SOURCE_RULES）。"
    lines << "YouTubeは名詞2〜3語、Blueskyは1〜2語のAND検索。"
    lines << ""

    Audience.order(:id).each do |audience|
      lines << "## #{audience.name}（#{audience.slug}）"
      lines << ""
      lines << "> #{audience.description}"
      lines << ""
      QueryGenerator::SOURCES.each do |source|
        queries = audience.audience_queries.for_source(source).active.order(:query)
        next if queries.empty?

        lines << "### #{source}（#{queries.size}件）"
        lines << ""
        lines << "| 検索語 | この語で拾える理由 |"
        lines << "|---|---|"
        queries.each { |q| lines << "| #{q.query} | #{reasons[q.query] || '（前回の生成）'} |" }
        lines << ""
      end
    end

    OUTPUT_PATH.dirname.mkpath
    OUTPUT_PATH.write(lines.join("\n"))
  end
end
