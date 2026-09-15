require "test_helper"

class AudienceQueryTest < ActiveSupport::TestCase
  test "同じオーディエンス・媒体で同じ検索語は登録できない" do
    existing = audience_queries(:web_youtube)
    duplicate = AudienceQuery.new(audience: existing.audience, source: existing.source,
                                  query: existing.query, generated_by: "ai")
    assert_not duplicate.valid?
  end

  test "source は既知の媒体だけ" do
    query = AudienceQuery.new(audience: audiences(:web_seisaku), source: "twitter",
                              query: "テスト", generated_by: "ai")
    assert_not query.valid?
  end

  test "active は有効な検索語だけを返す" do
    assert_includes AudienceQuery.active, audience_queries(:web_youtube)
    assert_not_includes AudienceQuery.active, audience_queries(:ec_youtube)
  end
end
