# このファイルはYouTubeの動画コメントを集めて posts に保存する。
# google-apis-youtube_v3 を使うのはこのファイルだけ（他の場所からAPIを直接触らない）。
# YouTubeは集計専用なので、投稿者名・チャンネル名・アイコンは一切保存しない。
module Sources
  class YoutubeSource
    # APIごとのクォータ単価（YouTube Data API v3 の公式値）
    SEARCH_COST = 100          # search.list を1回呼ぶと100ユニット
    COMMENT_THREADS_COST = 1   # commentThreads.list を1ページ読むと1ユニット

    # 1日の上限。これを超える前に止める
    DAILY_QUOTA_LIMIT = 10_000

    # 1回の実行での取りすぎを防ぐ上限
    MAX_VIDEOS_PER_QUERY = 10      # 検索語1つあたり何本の動画を見るか
    MAX_COMMENT_PAGES = 5          # 動画1本あたり何ページ読むか（1ページ100件）
    MIN_TEXT_LENGTH = 10           # これより短いコメントは捨てる（「草」「わかる」など）

    # 生投稿の保持期間。YouTubeの規約に合わせて30日で失効させ、以降は集計値だけ残す
    RETENTION_DAYS = 30

    # 検索語のうち「検討の観点」を表す語。どの業種にも出てくる一般語なので、
    # 動画が主題に合っているかの判定には使わない（例「サイト制作 見積もり 比較」の 見積もり・比較）
    ASPECT_WORDS = %w[
      費用 相場 価格 料金 比較 選び方 選定 見積もり 見積 外注 依頼 発注 流れ 手順
      トラブル 期間 納期 検討 おすすめ 方法 注意点
    ].freeze

    # 実行結果。rake タスクとジョブがこの中身をそのままログに出す
    Result = Struct.new(
      :query_count, :video_count, :saved_count, :skipped_count,
      :quota_used, :stopped_by_quota,
      keyword_init: true
    )

    def initialize(audience:, days: 7, quota_limit: DAILY_QUOTA_LIMIT, client: nil, logger: Rails.logger)
      @audience = audience
      @days = days
      @quota_limit = quota_limit
      @client = client || build_client
      @logger = logger

      # このクォータ集計は1回の実行のなかだけの数字。1日に何度も回すときは
      # quota_limit を小さくして渡す（例: 1日3回なら 3_000 ずつ）
      @quota_used = 0
      @stopped_by_quota = false
    end

    # 検索語ごとに「動画を探す → コメントを読む → 保存する」を直列で繰り返す
    def collect
      queries = @audience.audience_queries.active.for_source("youtube").order(:id)
      log "収集開始 audience=#{@audience.slug} 検索語=#{queries.size}件 直近#{@days}日 クォータ上限=#{@quota_limit}"

      result = Result.new(
        query_count: 0, video_count: 0, saved_count: 0, skipped_count: 0,
        quota_used: 0, stopped_by_quota: false
      )

      queries.each do |audience_query|
        break if @stopped_by_quota

        video_ids = search_video_ids(audience_query.query)
        break if @stopped_by_quota && video_ids.empty?

        result.query_count += 1
        result.video_count += video_ids.size

        video_ids.each do |video_id|
          break if @stopped_by_quota

          saved, skipped = collect_comments(video_id)
          result.saved_count += saved
          result.skipped_count += skipped
        end
      end

      result.quota_used = @quota_used
      result.stopped_by_quota = @stopped_by_quota
      log "収集終了 保存=#{result.saved_count}件 スキップ=#{result.skipped_count}件 " \
          "動画=#{result.video_count}本 使用クォータ=#{@quota_used}ユニット" \
          "#{@stopped_by_quota ? '（クォータ上限で中断）' : ''}"
      result
    end

    private

    def build_client
      api_key = ENV["YOUTUBE_API_KEY"]
      raise "YOUTUBE_API_KEY が設定されていません（.env を確認）" if api_key.blank?

      # gem の既定ログは Rails.logger と同じもので、リクエストURL（＝APIキー）まで出してしまう。
      # 専用の静かなロガーに差し替える（警告以上だけ標準エラーへ）
      Google::Apis.logger = Logger.new($stderr, level: Logger::WARN)

      client = Google::Apis::YoutubeV3::YouTubeService.new
      client.key = api_key
      client
    end

    # 検索語から動画IDを集める。search.list は1回100ユニットと高いので1検索語1回だけ呼ぶ
    def search_video_ids(query)
      return [] unless spend_quota(SEARCH_COST, "search.list q=#{query}")

      response = @client.list_searches(
        "id,snippet",
        q: query,
        type: "video",
        relevance_language: "ja",
        region_code: "JP",
        order: "relevance",
        published_after: @days.days.ago.utc.iso8601,
        max_results: MAX_VIDEOS_PER_QUERY
      )

      videos = response.items.filter_map { |item| item.id&.video_id&.then { |id| [ id, item.snippet ] } }

      # YouTubeの検索は全語のAND検索ではないので、主題と関係ない人気動画が混ざる
      # （「サイト制作 見積もり 比較」でiPhoneの価格比較動画が返る）。
      # タイトルか説明文に主題語が入っている動画だけに絞る。
      # どのチャンネルを拾ったかは検索語の見直しに必要なので、ログにだけ出す（保存はしない）
      matched = videos.select do |id, snippet|
        keep = on_topic?(query, snippet)
        log "  #{keep ? '候補' : '除外'} #{id} [#{snippet&.channel_title}] #{snippet&.title}"
        keep
      end

      log "検索 q=#{query} → 動画#{videos.size}本のうち主題に合う#{matched.size}本"
      matched.map(&:first)
    end

    # 検索語の主題語（観点の語を除いた残り）が、動画のタイトルか説明文に入っているか。
    # 主題語が無い検索語（観点の語だけ）のときは絞り込めないので通す
    def on_topic?(query, snippet)
      topics = query.split(/[[:space:]]+/).reject { |word| ASPECT_WORDS.include?(word) }
      return true if topics.empty?

      haystack = "#{snippet&.title} #{snippet&.description}".downcase
      topics.any? { |topic| haystack.include?(topic.downcase) }
    end

    # 動画1本のコメントを読んで保存する。戻り値は [保存件数, スキップ件数]
    def collect_comments(video_id)
      saved = 0
      skipped = 0
      page_token = nil

      MAX_COMMENT_PAGES.times do
        break unless spend_quota(COMMENT_THREADS_COST, "commentThreads.list video=#{video_id}")

        response = fetch_comment_threads(video_id, page_token)
        break if response.nil? # コメント無効の動画など

        response.items.each do |item|
          if save_post(video_id, item)
            saved += 1
          else
            skipped += 1
          end
        end

        page_token = response.next_page_token
        break if page_token.blank?
      end

      log "動画 #{video_id} → 保存#{saved}件 スキップ#{skipped}件"
      [ saved, skipped ]
    end

    def fetch_comment_threads(video_id, page_token)
      @client.list_comment_threads(
        "snippet",
        video_id: video_id,
        max_results: 100,
        order: "time",
        text_format: "plainText",
        page_token: page_token
      )
    rescue Google::Apis::ClientError => e
      # コメント無効・動画非公開はよくあることなので、この動画だけ飛ばして次へ進む。
      # それ以外のエラー（キー不正・クォータ切れなど）はそのまま落とす
      raise unless e.message.match?(/commentsDisabled|videoNotFound|forbidden/i)

      log "動画 #{video_id} はコメントを取得できないので飛ばす（#{e.class}）"
      nil
    end

    # コメント1件を posts に保存する。保存したら true、捨てた・既にあるなら false
    def save_post(video_id, thread)
      comment = thread.snippet&.top_level_comment
      snippet = comment&.snippet
      return false if snippet.nil?

      text = snippet.text_display.to_s.strip
      return false unless keep?(text)

      post = Post.find_or_initialize_by(source: "youtube", external_id: comment.id)
      return false if post.persisted? # 再実行しても重複しない

      fetched_at = Time.current
      post.assign_attributes(
        audience: @audience,
        text: text,
        posted_at: snippet.published_at,
        # 公開指標だけ。投稿者名・チャンネルIDは入れない
        metrics: {
          "like_count" => snippet.like_count.to_i,
          "reply_count" => thread.snippet.total_reply_count.to_i
        },
        video_id: video_id,
        fetched_at: fetched_at,
        expires_at: fetched_at + RETENTION_DAYS.days
      )
      post.save!
      true
    end

    # 日本語が含まれていて、ある程度の長さがあるものだけ残す
    def keep?(text)
      return false if text.length < MIN_TEXT_LENGTH

      text.match?(/[ぁ-んァ-ヶ一-龯]/)
    end

    # クォータを使ってよければ加算して true。上限に届くなら false（呼び出し側が止まる）
    def spend_quota(cost, label)
      if @quota_used + cost > @quota_limit
        @stopped_by_quota = true
        log "クォータ上限に達したので中断（使用#{@quota_used} + 次の#{cost} > 上限#{@quota_limit}）: #{label}"
        return false
      end

      @quota_used += cost
      true
    end

    def log(message)
      @logger.info "[youtube] #{message}"
    end
  end
end
