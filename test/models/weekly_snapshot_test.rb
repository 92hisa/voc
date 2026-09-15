require "test_helper"

class WeeklySnapshotTest < ActiveSupport::TestCase
  test "同じ週・レンズ・クラスタでは1件だけ" do
    existing = weekly_snapshots(:web_pain_snapshot)
    duplicate = WeeklySnapshot.new(audience: existing.audience, week_start: existing.week_start,
                                   lens: existing.lens, cluster: existing.cluster)
    assert_not duplicate.valid?
  end

  test "件数は負の数にできない" do
    snapshot = WeeklySnapshot.new(audience: audiences(:ec_unei), week_start: Date.new(2026, 9, 7),
                                  lens: "pain", cluster: clusters(:web_pain_cluster), post_count: -1)
    assert_not snapshot.valid?
  end

  test "by_post_count は件数の多い順" do
    snapshots = WeeklySnapshot.for_week(Date.new(2026, 9, 7)).by_post_count
    assert_equal weekly_snapshots(:web_pain_snapshot), snapshots.first
  end
end
