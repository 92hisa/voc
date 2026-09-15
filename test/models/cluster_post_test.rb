require "test_helper"

class ClusterPostTest < ActiveSupport::TestCase
  test "同じクラスタに同じ投稿は1回だけ" do
    duplicate = ClusterPost.new(cluster: clusters(:web_pain_cluster), post: posts(:web_pain))
    assert_not duplicate.valid?
  end
end
