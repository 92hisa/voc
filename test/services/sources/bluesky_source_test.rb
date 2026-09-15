# このファイルは BlueskySource のテスト。Faraday のテストアダプタで応答を差し込み、通信はしない。
require "test_helper"

class Sources::BlueskySourceTest < ActiveSupport::TestCase
  SEARCH_PATH = Sources::BlueskySource::SEARCH_POSTS_PATH
  SESSION_PATH = Sources::BlueskySource::CREATE_SESSION_PATH

  setup do
    ENV["BLUESKY_HANDLE"] = "test.bsky.social"
    ENV["BLUESKY_APP_PASSWORD"] = "test-pass"
  end

  def build_post(uri:, text:, like_count: 0, reply_count: 0, created_at: 2.days.ago)
    {
      "uri" => uri,
      "cid" => "cid-#{uri}",
      # 表示名・アバターが返ってきても保存しないことを確かめるために入れておく
      "author" => { "did" => "did:plc:abc", "handle" => "someone.bsky.social",
                    "displayName" => "なまえ", "avatar" => "https://example.com/a.jpg" },
      "record" => { "text" => text, "createdAt" => created_at.utc.iso8601, "langs" => [ "ja" ] },
      "likeCount" => like_count,
      "replyCount" => reply_count,
      "repostCount" => 0,
      "quoteCount" => 0
    }
  end

  # pages は [[投稿の配列, 次のカーソル], ...]。検索語1つぶんの応答を順に返す
  def collect_with(pages, session: { "accessJwt" => "test-token" })
    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.post(SESSION_PATH) { [ 200, { "Content-Type" => "application/json" }, session.to_json ] }
    requests = []
    pages.each do |posts, cursor|
      stubs.get(SEARCH_PATH) do |env|
        requests << env
        [ 200, { "Content-Type" => "application/json" }, { "posts" => posts, "cursor" => cursor }.to_json ]
      end
    end

    connection = Faraday.new do |f|
      f.request :json
      f.response :json
      f.response :raise_error
      f.adapter :test, stubs
    end

    source = Sources::BlueskySource.new(
      audience: audiences(:web_seisaku), days: 7,
      connection: connection, logger: ActiveSupport::Logger.new(IO::NULL)
    )
    [ source.collect, requests ]
  end

  test "投稿を保存し、表示名は保存しない" do
    posts = [ build_post(uri: "at://did:plc:abc/app.bsky.feed.post/1",
                         text: "ホームページを頼みたいけど、どこに相談すればいいのか分からない", like_count: 3, reply_count: 1) ]

    result, requests = collect_with([ [ posts, nil ] ])

    assert_equal 1, result.saved_count
    stored = Post.find_by!(source: "bluesky", external_id: "at://did:plc:abc/app.bsky.feed.post/1")
    assert_equal audiences(:web_seisaku), stored.audience
    assert_equal 3, stored.metrics["like_count"]
    assert_equal 1, stored.metrics["reply_count"]
    assert_not_nil stored.expires_at
    assert_nil stored.video_id
    # 表示名やハンドルがどのカラムにも入っていない
    assert_not stored.attributes.values.map(&:to_s).any? { |value| value.include?("なまえ") || value.include?("someone") }

    # 検索の条件（日本語・直近7日・新しい順）
    params = requests.first.params
    assert_equal "サイト 作りたい", params["q"]
    assert_equal "ja", params["lang"]
    assert_equal "latest", params["sort"]
    assert params["since"].present?
    assert_equal "Bearer test-token", requests.first.request_headers["Authorization"]
  end

  test "短い投稿と日本語でない投稿は保存しない" do
    posts = [
      build_post(uri: "at://x/1", text: "わかる"),
      build_post(uri: "at://x/2", text: "I want to build a website for my shop"),
      build_post(uri: "at://x/3", text: "サイトのリニューアルを誰かに頼みたい")
    ]

    result, _requests = collect_with([ [ posts, nil ] ])

    assert_equal 1, result.saved_count
    assert_equal 2, result.skipped_count
    assert_nil Post.find_by(external_id: "at://x/1")
  end

  test "カーソルがある間はページをめくる" do
    page1 = [ build_post(uri: "at://x/1", text: "ホームページの制作を頼みたいと思っています") ]
    page2 = [ build_post(uri: "at://x/2", text: "サイトの見積もりが高くて悩んでいます") ]

    result, requests = collect_with([ [ page1, "cursor-1" ], [ page2, nil ] ])

    assert_equal 2, result.saved_count
    assert_equal 2, requests.size
    assert_equal "cursor-1", requests.second.params["cursor"]
  end

  test "2回実行しても同じ投稿を二重に保存しない" do
    posts = [ build_post(uri: "at://x/1", text: "ホームページの制作を頼みたいと思っています") ]

    first, _ = collect_with([ [ posts, nil ] ])
    second, _ = collect_with([ [ posts, nil ] ])

    assert_equal 1, first.saved_count
    assert_equal 0, second.saved_count
    assert_equal 1, second.skipped_count
    assert_equal 1, Post.where(external_id: "at://x/1").count
  end

  test "ログインに失敗したら保存せずに落ちる" do
    before = Post.for_source("bluesky").count

    error = assert_raises(RuntimeError) { collect_with([ [ [], nil ] ], session: { "error" => "AuthenticationRequired" }) }

    assert_match "ログインに失敗", error.message
    assert_equal before, Post.for_source("bluesky").count
  end
end
