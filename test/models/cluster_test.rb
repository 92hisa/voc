require "test_helper"

class ClusterTest < ActiveSupport::TestCase
  test "投稿とつながっている" do
    assert_equal [ posts(:web_pain) ], clusters(:web_pain_cluster).posts.to_a
  end

  test "lens は5つのレンズ（＋noise）だけ" do
    cluster = Cluster.new(audience: audiences(:web_seisaku), lens: "unknown_lens",
                          week_start: Date.new(2026, 9, 7), name: "テスト")
    assert_not cluster.valid?
  end
end
