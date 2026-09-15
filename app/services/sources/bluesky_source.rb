# このファイルはBluesky（AT Protocol）の投稿を集めて posts に保存する。
# Faraday でXRPCを直接叩く薄いクライアントで、Blueskyを触るのはこのファイルだけ。
# 保存するのは投稿URI・本文・日時・公開指標だけ（表示名・アバター・プロフィールは保存しない。
# 投稿URIにDIDが入るが、これは投稿IDそのもので、後で author_count を数えるのにも使う）。
module Sources
  class BlueskySource
    # 認証（createSession）も検索（searchPosts）も自分のPDS経由で叩ける
    HOST = "https://bsky.social"
    CREATE_SESSION_PATH = "/xrpc/com.atproto.server.createSession"
    SEARCH_POSTS_PATH = "/xrpc/app.bsky.feed.searchPosts"

    # 1回の取りすぎを防ぐ上限
    PAGE_SIZE = 100            # searchPosts の1ページあたり件数（APIの上限が100）
    MAX_PAGES = 5              # 検索語1つあたり何ページ読むか（最大500件）
    MIN_TEXT_LENGTH = 10       # これより短い投稿は捨てる

    # 生投稿の保持期間。元の投稿が消されたときに残り続けないよう長く持たない
    RETENTION_DAYS = 30

    Result = Struct.new(
      :query_count, :fetched_count, :saved_count, :skipped_count,
      keyword_init: true
    )

    def initialize(audience:, days: 7, connection: nil, logger: Rails.logger)
      @audience = audience
      @days = days
      @connection = connection || build_connection
      @logger = logger
    end

    # 検索語ごとに「投稿を検索する → 保存する」を直列で繰り返す
    def collect
      queries = @audience.audience_queries.active.for_source("bluesky").order(:id)
      log "収集開始 audience=#{@audience.slug} 検索語=#{queries.size}件 直近#{@days}日"

      login

      result = Result.new(query_count: 0, fetched_count: 0, saved_count: 0, skipped_count: 0)

      queries.each do |audience_query|
        fetched, saved, skipped = collect_query(audience_query.query)
        result.query_count += 1
        result.fetched_count += fetched
        result.saved_count += saved
        result.skipped_count += skipped
      end

      log "収集終了 取得=#{result.fetched_count}件 保存=#{result.saved_count}件 スキップ=#{result.skipped_count}件"
      result
    end

    private

    def build_connection
      Faraday.new(url: HOST) do |f|
        f.request :json
        f.response :json
        f.response :raise_error # 失敗したらDBに書く前に例外で落とす
        f.options.timeout = 30
      end
    end

    # ハンドル＋アプリパスワードでセッションを作る。以降は accessJwt を付けて叩く
    def login
      handle = ENV["BLUESKY_HANDLE"]
      password = ENV["BLUESKY_APP_PASSWORD"]
      raise "BLUESKY_HANDLE / BLUESKY_APP_PASSWORD が設定されていません（.env を確認）" if handle.blank? || password.blank?

      response = @connection.post(CREATE_SESSION_PATH, { identifier: handle, password: password })
      @token = response.body["accessJwt"]
      raise "Blueskyのログインに失敗しました（accessJwt が返ってきません）" if @token.blank?

      log "ログイン成功 handle=#{handle}"
    end

    # 検索語1つ分。戻り値は [取得件数, 保存件数, スキップ件数]
    def collect_query(query)
      fetched = 0
      saved = 0
      skipped = 0
      cursor = nil

      MAX_PAGES.times do
        posts, cursor = search(query, cursor)
        fetched += posts.size

        posts.each do |post|
          if save_post(post)
            saved += 1
          else
            skipped += 1
          end
        end

        break if cursor.blank? || posts.empty?
      end

      log "検索 q=#{query} → 取得#{fetched}件 保存#{saved}件 スキップ#{skipped}件"
      [ fetched, saved, skipped ]
    end

    # searchPosts を1ページ読む。戻り値は [投稿の配列, 次のカーソル]
    def search(query, cursor)
      response = @connection.get(SEARCH_POSTS_PATH) do |request|
        request.headers["Authorization"] = "Bearer #{@token}"
        request.params = {
          q: query,
          lang: "ja",                              # 日本語の投稿だけ
          since: @days.days.ago.utc.iso8601,       # 直近N日
          sort: "latest",
          limit: PAGE_SIZE,
          cursor: cursor
        }.compact
      end

      [ Array(response.body["posts"]), response.body["cursor"] ]
    end

    # 投稿1件を posts に保存する。保存したら true、捨てた・既にあるなら false
    def save_post(post)
      uri = post["uri"]
      record = post["record"] || {}
      text = record["text"].to_s.strip
      return false if uri.blank? || !keep?(text)

      stored = Post.find_or_initialize_by(source: "bluesky", external_id: uri)
      return false if stored.persisted? # 再実行しても重複しない

      fetched_at = Time.current
      stored.assign_attributes(
        audience: @audience,
        text: text,
        posted_at: record["createdAt"],
        # 公開指標だけ。表示名・アバターは入れない
        metrics: {
          "like_count" => post["likeCount"].to_i,
          "reply_count" => post["replyCount"].to_i,
          "repost_count" => post["repostCount"].to_i,
          "quote_count" => post["quoteCount"].to_i
        },
        fetched_at: fetched_at,
        expires_at: fetched_at + RETENTION_DAYS.days
      )
      stored.save!
      true
    end

    # 日本語が含まれていて、ある程度の長さがあるものだけ残す
    # （lang=ja で絞っていても、英語だけの投稿や絵文字だけの投稿が混ざる）
    def keep?(text)
      return false if text.length < MIN_TEXT_LENGTH

      text.match?(/[ぁ-んァ-ヶ一-龯]/)
    end

    def log(message)
      @logger.info "[bluesky] #{message}"
    end
  end
end
