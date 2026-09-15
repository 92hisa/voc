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

    # 共通の方針
    - 売り手（制作会社・代理店・フリーランス・コンサル）の宣伝や、
      ノウハウ解説チャンネルばかりが引っかかる語は作らない
    - 「集客」「ノウハウ」「稼ぐ」「講座」「解説」「おすすめ10選」のような
      発信者side（売り手）の語彙は入れない
    - 媒体ごとの書き方（次の節）を必ず守る。媒体によって検索の仕組みが違う

    # 出力
    JSONだけを返す。説明文やコードブロックは付けない。
    {"queries": [{"query": "検索語", "reason": "この語で頼む側の投稿が拾える理由（40字以内）"}]}
  PROMPT

  # 媒体ごとの書き方。YouTubeとBlueskyで検索の対象が違うので、方針を分ける
  SOURCE_RULES = {
    "youtube" => <<~RULE,
      # youtube の書き方
      YouTubeの検索は「動画のタイトル・説明文」への緩い一致で、全語のAND検索ではない。
      気持ちや状況の語を入れると、その語だけが効いて無関係な人気動画が返る。

      - 名詞中心の主題語を2〜3語だけ並べる
      - 「サービスや作業の名前」＋「検討するときの観点」の組み合わせにする
        観点の例: 相場／費用／見積もり／選び方／比較／外注／依頼／発注／リニューアル／乗り換え
      - 気持ちや状況の語は入れない（頼みたい／困った／どうすれば／後悔／迷う／怖い／失敗）
      - 話し言葉・助詞・疑問形は入れない

      良い例: ホームページ制作 相場 ／ 制作会社 選び方 ／ LP制作 外注 費用 ／ サイト リニューアル 見積もり
      悪い例とその理由:
      - 「サイト リニューアル 依頼 どうすれば」… 「どうすれば」が効いて選挙解説やゲーム動画が返った
      - 「サイト制作 予算 削りたい 相談」… 無関係な短編ドラマが大量に返った
      - 「ホームページ 作ってもらった 使いにくい」… 投資・政治系の動画が返った
      - 「ホームページ 問い合わせ 来ない」… 売り手の集客ノウハウ動画ばかり返った
    RULE
    "bluesky" => <<~RULE
      # bluesky の書き方
      Blueskyの検索は「投稿の本文」に当たるので、実際のつぶやきの言い回しをそのまま狙える。
      ただし**書いた語を全部含む投稿しか返らない（AND検索）**。日本語の利用者は多くないので、
      語を増やすとすぐ0件になる（「web制作 断られた」は0件、「サイト 作りたい」は100件）。

      - **1〜2語まで。3語以上は作らない**
      - 半分は「主題語1語だけ」（例: ホームページ制作／web制作／制作会社）で量を取る
      - 残りは「主題語＋買う側の短い動詞・形容詞」1語（例: 作りたい／頼みたい／高い／探してる）
      - 長い言い回し・助詞・疑問形は入れない（「どこに頼む」「どうすれば」は当たらない）

      良い例: ホームページ 作りたい ／ サイト 作りたい ／ web制作 ／ ホームページ 高い ／ 制作会社
      悪い例: web制作 見積もり 高い（3語で0件）／ サイトリニューアル どこに頼む（0件）
    RULE
  }.freeze

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
      system_: [ { type: "text", text: "#{SYSTEM_PROMPT}\n#{SOURCE_RULES.fetch(source)}" } ],
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
