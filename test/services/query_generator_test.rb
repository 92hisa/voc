# このファイルは QueryGenerator のテスト。AIは呼ばずに、偽のクライアントに決めた返事をさせる。
require "test_helper"

class QueryGeneratorTest < ActiveSupport::TestCase
  # Anthropic::Client の代わり。messages.create に決めた文字列を返させる
  class FakeClient
    Block = Struct.new(:type, :text)
    Response = Struct.new(:content)

    attr_reader :prompts, :systems

    def initialize(reply)
      @reply = reply
      @prompts = []
      @systems = []
    end

    def messages
      self
    end

    def create(**options)
      @prompts << options[:messages].first[:content]
      @systems << options[:system_].first[:text]
      Response.new([ Block.new(:text, @reply) ])
    end
  end

  def generate(reply, sources: [ "youtube" ], deactivate_existing: true)
    client = FakeClient.new(reply)
    generator = QueryGenerator.new(
      audience: audiences(:web_seisaku),
      client: client,
      model: "claude-opus-5",
      logger: ActiveSupport::Logger.new(IO::NULL)
    )
    [ generator.generate(sources: sources, deactivate_existing: deactivate_existing), client ]
  end

  def reply_with(*queries)
    { "queries" => queries.map { |q| { "query" => q, "reason" => "頼む側の言い回し" } } }.to_json
  end

  test "生成した検索語を generated_by=ai で保存する" do
    results, client = generate(reply_with("ホームページ 制作 頼みたい", "web制作 見積もり 高い"))

    assert_equal 1, results.size
    assert_equal 2, results.first.saved_count

    saved = audiences(:web_seisaku).audience_queries.for_source("youtube").active.order(:query)
    assert_equal [ "web制作 見積もり 高い", "ホームページ 制作 頼みたい" ], saved.pluck(:query).sort
    assert_equal [ "ai" ], saved.pluck(:generated_by).uniq
    assert_match "Web制作を頼む人", client.prompts.first
    assert_match "媒体: youtube", client.prompts.first
  end

  test "媒体ごとの書き方をシステムプロンプトに入れる" do
    _results, client = generate(reply_with("ホームページ制作 相場"), sources: [ "youtube", "bluesky" ])

    assert_match "名詞中心の主題語を2〜3語だけ並べる", client.systems.first
    assert_no_match(/名詞中心の主題語/, client.systems.second)
    assert_match "1〜2語まで", client.systems.second
  end

  test "同じ媒体の既存の検索語は is_active=false にする" do
    old = audience_queries(:web_youtube)
    assert old.is_active

    generate(reply_with("ホームページ 制作 頼みたい"))

    assert_not old.reload.is_active
    # 別の媒体（bluesky）の検索語はそのまま
    assert audience_queries(:web_bluesky).reload.is_active
  end

  test "deactivate_existing: false なら既存の検索語を残す" do
    generate(reply_with("ホームページ 制作 頼みたい"), deactivate_existing: false)

    assert audience_queries(:web_youtube).reload.is_active
  end

  test "同じ語が既にあれば作り直さず有効にする" do
    existing = audience_queries(:web_youtube)

    results, _client = generate(reply_with(existing.query, "web制作 見積もり 高い"))

    assert_equal 2, results.first.saved_count
    assert existing.reload.is_active
    assert_equal "ai", existing.generated_by # 人手で入れた語はそのまま
    assert_equal 1, AudienceQuery.where(audience: audiences(:web_seisaku), source: "youtube", query: existing.query).count
  end

  test "コードブロックで囲まれたJSONでも読める" do
    reply = "```json\n#{reply_with('ホームページ 制作 頼みたい')}\n```"

    results, _client = generate(reply)

    assert_equal 1, results.first.saved_count
  end

  test "重複した検索語はまとめる" do
    reply = reply_with("ホームページ 制作 頼みたい", "ホームページ 制作 頼みたい", "web制作 見積もり 高い")

    results, _client = generate(reply)

    assert_equal 2, results.first.saved_count
  end

  test "JSONでない返事のときは保存せずに落とす" do
    error = assert_raises(RuntimeError) { generate("検索語はこちらです") }
    assert_match "JSONではありません", error.message

    # 既存の検索語も触らない
    assert audience_queries(:web_youtube).reload.is_active
  end

  test "検索語が空のときは落とす" do
    error = assert_raises(RuntimeError) { generate({ "queries" => [] }.to_json) }
    assert_match "検索語を作れませんでした", error.message
  end

  test "15個より多く返ってきたら15個に切る" do
    reply = reply_with(*(1..20).map { |i| "検索語#{i}" })

    results, _client = generate(reply)

    assert_equal QueryGenerator::COUNT_MAX, results.first.saved_count
  end
end
