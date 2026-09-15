require "test_helper"

class PostTest < ActiveSupport::TestCase
  test "同じ媒体・同じ投稿IDは保存できない" do
    existing = posts(:web_pain)
    duplicate = Post.new(audience: existing.audience, source: existing.source,
                         external_id: existing.external_id, text: "重複", posted_at: Time.current,
                         fetched_at: Time.current)
    assert_not duplicate.valid?
  end

  test "媒体が違えば同じ投稿IDでも保存できる" do
    existing = posts(:web_pain)
    post = Post.new(audience: existing.audience, source: "bluesky",
                    external_id: existing.external_id, text: "別媒体", posted_at: Time.current,
                    fetched_at: Time.current)
    assert post.valid?
  end

  test "metrics は JSON として読み書きできる" do
    assert_equal 12, posts(:web_pain).metrics["like_count"]
  end

  test "unclassified は分類がまだの投稿を返す" do
    post = Post.create!(audience: audiences(:web_seisaku), source: "bluesky",
                        external_id: "at://example/post/new", text: "未分類の投稿",
                        posted_at: Time.current, fetched_at: Time.current)
    assert_includes Post.unclassified, post
    assert_not_includes Post.unclassified, posts(:web_pain)
  end

  test "expired は保持期限を過ぎた投稿を返す" do
    assert_includes Post.expired(Time.zone.parse("2026-11-01")), posts(:web_pain)
    assert_empty Post.expired(Time.zone.parse("2026-09-15"))
  end
end
