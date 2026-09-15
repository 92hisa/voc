# このファイルは YoutubeSource のテスト。APIは呼ばずに、偽のクライアントを差し込んで確かめる。
require "test_helper"

class Sources::YoutubeSourceTest < ActiveSupport::TestCase
  # Google のクライアントの代わりに使う。決めた応答をそのまま返すだけ
  class FakeClient
    attr_reader :searched_queries, :comment_calls

    def initialize(video_ids:, threads:, video_titles: {})
      @video_ids = video_ids
      @threads = threads
      @video_titles = video_titles
      @searched_queries = []
      @comment_calls = []
    end

    def list_searches(_part, **options)
      @searched_queries << options[:q]
      items = @video_ids.map do |video_id|
        Google::Apis::YoutubeV3::SearchResult.new(
          id: Google::Apis::YoutubeV3::ResourceId.new(video_id: video_id),
          snippet: Google::Apis::YoutubeV3::SearchResultSnippet.new(
            title: @video_titles.fetch(video_id, "ホームページ 制作 依頼の流れ"),
            description: "",
            channel_title: "テストチャンネル"
          )
        )
      end
      Google::Apis::YoutubeV3::SearchListsResponse.new(items: items)
    end

    def list_comment_threads(_part, **options)
      @comment_calls << options[:video_id]
      Google::Apis::YoutubeV3::ListCommentThreadsResponse.new(items: @threads, next_page_token: nil)
    end
  end

  def build_thread(id:, text:, like_count: 0, reply_count: 0, published_at: 2.days.ago)
    Google::Apis::YoutubeV3::CommentThread.new(
      snippet: Google::Apis::YoutubeV3::CommentThreadSnippet.new(
        total_reply_count: reply_count,
        top_level_comment: Google::Apis::YoutubeV3::Comment.new(
          id: id,
          snippet: Google::Apis::YoutubeV3::CommentSnippet.new(
            text_display: text,
            like_count: like_count,
            published_at: published_at
          )
        )
      )
    )
  end

  def collect_with(threads, video_ids: [ "video-1" ], video_titles: {}, quota_limit: Sources::YoutubeSource::DAILY_QUOTA_LIMIT)
    client = FakeClient.new(video_ids: video_ids, threads: threads, video_titles: video_titles)
    source = Sources::YoutubeSource.new(
      audience: audiences(:web_seisaku),
      days: 7,
      quota_limit: quota_limit,
      client: client,
      logger: ActiveSupport::Logger.new(IO::NULL)
    )
    [ source.collect, client ]
  end

  test "コメントを posts に保存し、いいね数を metrics に入れる" do
    threads = [ build_thread(id: "comment-1", text: "ホームページを作ったのに問い合わせがゼロで困っています", like_count: 5, reply_count: 2) ]

    result, client = collect_with(threads)

    assert_equal 1, result.saved_count
    assert_equal [ "ホームページ 制作 依頼" ], client.searched_queries

    post = Post.find_by!(source: "youtube", external_id: "comment-1")
    assert_equal audiences(:web_seisaku), post.audience
    assert_equal "video-1", post.video_id
    assert_equal 5, post.metrics["like_count"]
    assert_equal 2, post.metrics["reply_count"]
    assert_not_nil post.expires_at
  end

  test "短い投稿と日本語でない投稿は保存しない" do
    threads = [
      build_thread(id: "comment-short", text: "草"),
      build_thread(id: "comment-en", text: "This is a great video, thanks!"),
      build_thread(id: "comment-ok", text: "制作会社に見積もりを出したら50万円でした")
    ]

    result, _client = collect_with(threads)

    assert_equal 1, result.saved_count
    assert_equal 2, result.skipped_count
    assert_nil Post.find_by(external_id: "comment-short")
    assert_nil Post.find_by(external_id: "comment-en")
  end

  test "2回実行しても同じ投稿を二重に保存しない" do
    threads = [ build_thread(id: "comment-1", text: "ホームページのリニューアルを頼みたいのですが相場が分かりません") ]

    first, _ = collect_with(threads)
    second, _ = collect_with(threads)

    assert_equal 1, first.saved_count
    assert_equal 0, second.saved_count
    assert_equal 1, second.skipped_count
    assert_equal 1, Post.where(external_id: "comment-1").count
  end

  test "主題と関係ない動画はコメントを読まない" do
    threads = [ build_thread(id: "comment-1", text: "ホームページの制作費用が高くて悩んでいます") ]

    # 検索語「ホームページ 制作 依頼」の主題語が入っていないタイトル
    result, client = collect_with(
      threads,
      video_ids: [ "video-1", "video-2" ],
      video_titles: { "video-1" => "iPhone18 Pro 価格比較、キャリア購入は慎重に" }
    )

    assert_equal [ "video-2" ], client.comment_calls
    assert_equal 1, result.video_count
    assert_equal 100 + 1, result.quota_used
  end

  test "説明文に主題語があれば読む" do
    threads = [ build_thread(id: "comment-1", text: "ホームページの制作費用が高くて悩んでいます") ]
    client = FakeClient.new(video_ids: [ "video-1" ], threads: threads, video_titles: { "video-1" => "無題" })
    client.define_singleton_method(:list_searches) do |_part, **options|
      @searched_queries << options[:q]
      Google::Apis::YoutubeV3::SearchListsResponse.new(items: [
        Google::Apis::YoutubeV3::SearchResult.new(
          id: Google::Apis::YoutubeV3::ResourceId.new(video_id: "video-1"),
          snippet: Google::Apis::YoutubeV3::SearchResultSnippet.new(
            title: "無題", description: "ホームページを作りたい人向けの回", channel_title: "テスト"
          )
        )
      ])
    end
    source = Sources::YoutubeSource.new(
      audience: audiences(:web_seisaku), days: 7, client: client, logger: ActiveSupport::Logger.new(IO::NULL)
    )

    assert_equal 1, source.collect.saved_count
  end

  test "クォータ上限を超える前に止める" do
    threads = [ build_thread(id: "comment-1", text: "ホームページの制作費用が高くて悩んでいます") ]

    # search.list は100ユニットかかるので、上限50なら1回も検索しないで止まる
    result, client = collect_with(threads, quota_limit: 50)

    assert result.stopped_by_quota
    assert_equal 0, result.quota_used
    assert_equal 0, result.saved_count
    assert_empty client.comment_calls
  end

  test "使ったクォータを数える（検索100＋コメント1ページ1）" do
    threads = [ build_thread(id: "comment-1", text: "ホームページの制作費用が高くて悩んでいます") ]

    result, _client = collect_with(threads, video_ids: [ "video-1", "video-2" ])

    assert_equal 100 + 2, result.quota_used
    assert_equal 2, result.video_count
    assert_not result.stopped_by_quota
  end
end
