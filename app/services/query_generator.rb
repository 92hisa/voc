# このファイルはオーディエンスの説明から、媒体別の検索語をAIで作って audience_queries に保存する。
# 検索語の方針は「頼む側・買う側が打つ言葉」。売り手の宣伝が混ざる語は作らせない（SYSTEM_PROMPT）。
class QueryGenerator
  SOURCES = %w[youtube bluesky].freeze
  COUNT_MIN = 10
  COUNT_MAX = 15

  # ENV["AI_MODEL"] が空のときに使うモデル
  DEFAULT_MODEL = "claude-opus-5"

  # 1媒体あたりの生成結果。rake タスクがこれを docs/eval/queries.md に書き出す
  Result = Struct.new(:source, :queries, :saved_count, :deactivated_count, keyword_init: true)

  SYSTEM_PROMPT = <<~PROMPT.freeze
    あなたは日本語のSNS・動画の検索語を設計する担当者です。
    目的は「そのサービスを頼みたい・買いたい側の人」が書いた投稿を見つけることです。

    # 必ず守る方針
    - 検索語は「頼む側・買う側」が実際に打つ言葉にする（依頼したい／比較したい／不安・お金の話）
    - 売り手（制作会社・代理店・フリーランス・コンサル）の宣伝や、
      ノウハウ解説チャンネルばかりが引っかかる語は作らない
    - 「集客」「ノウハウ」「稼ぐ」「講座」「解説」「おすすめツール10選」のような
      発信者side（売り手）の語彙は入れない
    - 業種や作業の名前だけの広い語（例:「ホームページ」）は作らない。必ず気持ちや状況を足す

    # 良い例（頼む側の言い回し）
    - ホームページ 制作 頼みたい
    - web制作 見積もり 高い
    - 制作会社 選び方 迷う
    - サイト リニューアル 相談

    # 悪い例とその理由
    - 「ホームページ 問い合わせ 来ない」… 売り手の集客ノウハウ動画や無関係なチャンネルが大量に混ざる
    - 「web集客 方法」… 売り手の宣伝しか出ない
    - 「ホームページ制作」… 制作会社の宣伝しか出ない

    # 媒体ごとの書き方
    - youtube: 空白区切りのキーワード2〜4語。動画のコメント欄に頼む側がいそうな語
    - bluesky: 実際のつぶやきに出てくる短い言い回し（1〜3語、話し言葉でよい）

    # 出力
    JSONだけを返す。説明文やコードブロックは付けない。
    {"queries": [{"query": "検索語", "reason": "この語で頼む側の投稿が拾える理由（40字以内）"}]}
  PROMPT

  def initialize(audience:, client: nil, model: nil, logger: Rails.logger)
    @audience = audience
    @client = client || build_client
    @model = model.presence || ENV["AI_MODEL"].presence || DEFAULT_MODEL
    @logger = logger
  end

  # 媒体ごとに1回ずつAIを呼び、audience_queries に generated_by=ai で保存する。
  # deactivate_existing が true なら、その媒体の既存の検索語をいったん is_active=false にしてから
  # 今回の生成結果だけを有効にする（仮に入れた検索語を作り直すときの動き）
  def generate(sources: SOURCES, deactivate_existing: true)
    sources.map do |source|
      queries = ask_ai(source)

      deactivated = deactivate_existing ? deactivate(source) : 0
      saved = save(source, queries)

      log "#{@audience.slug}/#{source} 生成#{queries.size}件 有効化#{saved}件 無効化#{deactivated}件"
      Result.new(source: source, queries: queries, saved_count: saved, deactivated_count: deactivated)
    end
  end

  private

  def build_client
    raise "ANTHROPIC_API_KEY が設定されていません（.env を確認）" if ENV["ANTHROPIC_API_KEY"].blank?

    Anthropic::Client.new
  end

  # AIに検索語を作らせて [{ "query" =>, "reason" => }, ...] を返す
  def ask_ai(source)
    response = @client.messages.create(
      model: @model,
      max_tokens: 4_000, # 検索語15個ぶんのJSONなので短い
      system_: [ { type: "text", text: SYSTEM_PROMPT } ],
      messages: [ { role: "user", content: user_prompt(source) } ]
    )

    text = response.content.select { |block| block.type == :text }.map(&:text).join
    parse(text, source)
  end

  def user_prompt(source)
    <<~PROMPT
      オーディエンス名: #{@audience.name}
      説明: #{@audience.description}
      媒体: #{source}

      この人たちが書いた投稿を見つけるための検索語を#{COUNT_MIN}〜#{COUNT_MAX}個、JSONで出してください。
    PROMPT
  end

  # AIの返事はJSONのはずだが、コードブロックで囲まれることがあるので取り除いてから読む。
  # 読めなかったら（DBに何も書かずに）ここで落とす
  def parse(text, source)
    json = text.strip.sub(/\A```(?:json)?/, "").sub(/```\z/, "").strip
    parsed = JSON.parse(json)

    queries = Array(parsed["queries"])
      .map { |item| { "query" => item["query"].to_s.strip, "reason" => item["reason"].to_s.strip } }
      .reject { |item| item["query"].blank? }
      .uniq { |item| item["query"] }

    raise "検索語を作れませんでした（#{@audience.slug}/#{source}）: #{text.truncate(200)}" if queries.empty?

    log "#{@audience.slug}/#{source} は#{COUNT_MIN}件未満しか出なかった（#{queries.size}件）" if queries.size < COUNT_MIN
    queries.first(COUNT_MAX)
  rescue JSON::ParserError => e
    raise "AIの返事がJSONではありません（#{@audience.slug}/#{source}）: #{e.message} / #{text.truncate(200)}"
  end

  def deactivate(source)
    @audience.audience_queries.for_source(source).active.update_all(is_active: false, updated_at: Time.current)
  end

  def save(source, queries)
    queries.count do |item|
      audience_query = @audience.audience_queries.find_or_initialize_by(source: source, query: item["query"])
      # 同じ語を人手で登録していたら generated_by はそのまま残す
      audience_query.generated_by = "ai" if audience_query.new_record?
      audience_query.is_active = true
      audience_query.save!
    end
  end

  def log(message)
    @logger.info "[queries] #{message}"
  end
end
