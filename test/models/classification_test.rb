require "test_helper"

class ClassificationTest < ActiveSupport::TestCase
  test "1投稿につき1件だけ" do
    duplicate = Classification.new(post: posts(:web_pain), lens: "pain", side: "buyer",
                                   intent: "now", model: "claude-test", classified_at: Time.current)
    assert_not duplicate.valid?
  end

  test "lens・side・intent は決められた値だけ" do
    classification = Classification.new(post: posts(:ec_money), lens: "unknown_lens", side: "buyer",
                                        intent: "now", model: "claude-test", classified_at: Time.current)
    assert_not classification.valid?
    assert_includes classification.errors.attribute_names, :lens
  end

  test "buyer スコープは買う側の投稿だけを返す" do
    assert_includes Classification.buyer, classifications(:web_pain)
    assert_not_includes Classification.buyer, classifications(:ec_money)
  end
end
