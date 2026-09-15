# このファイルは検索語をAIで作る rake タスク。
# 例: bin/rails queries:generate          （全オーディエンス）
#     bin/rails queries:generate[web-seisaku]
namespace :queries do
  OUTPUT_PATH = Rails.root.join("docs/eval/queries.md")

  desc "検索語をAIで生成して audience_queries に保存する queries:generate[slug]"
  task :generate, [ :slug ] => :environment do |_task, args|
    audiences = args[:slug] ? [ Audience.find_by!(slug: args[:slug]) ] : Audience.order(:id).to_a
    abort "オーディエンスがありません。bin/rails seed:audiences を先に実行してください。" if audiences.empty?

    # 生成の進み具合を画面にも出す
    console = ActiveSupport::Logger.new($stdout, level: :info)
    console.formatter = ->(_severity, _time, _progname, message) { "#{message}\n" }
    Rails.logger.broadcast_to(console)

    generated = audiences.map { |audience| [ audience, QueryGenerator.new(audience: audience).generate ] }

    write_markdown(generated)
    puts
    puts "── 生成結果（#{OUTPUT_PATH.relative_path_from(Rails.root)} に出力）──"
    generated.each do |audience, results|
      results.each do |result|
        puts "#{audience.slug} / #{result.source}: 有効#{result.saved_count}件（旧#{result.deactivated_count}件を無効化）"
      end
    end
  end

  # 人が読んで検索語の良し悪しを確かめるための一覧。DBには理由を保存しないのでここに残す
  def write_markdown(generated)
    lines = [ "# 検索語の生成結果", "", "生成日時: #{Time.current.strftime('%Y-%m-%d %H:%M')}（モデル: #{ENV['AI_MODEL'].presence || QueryGenerator::DEFAULT_MODEL}）", "" ]
    lines << "方針は「頼む側・買う側が打つ言葉」。売り手の宣伝が混ざる語は避ける（`app/services/query_generator.rb` の SYSTEM_PROMPT）。"
    lines << ""

    generated.each do |audience, results|
      lines << "## #{audience.name}（#{audience.slug}）"
      lines << ""
      lines << "> #{audience.description}"
      lines << ""
      results.each do |result|
        lines << "### #{result.source}（#{result.queries.size}件）"
        lines << ""
        lines << "| 検索語 | この語で拾える理由 |"
        lines << "|---|---|"
        result.queries.each { |item| lines << "| #{item['query']} | #{item['reason']} |" }
        lines << ""
      end
    end

    OUTPUT_PATH.dirname.mkpath
    OUTPUT_PATH.write(lines.join("\n"))
  end
end
