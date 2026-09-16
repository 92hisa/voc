# このファイルはThreads（Meta）の公式APIを叩く。Threadsを触るのはこのファイルだけ。
# 2つの役割がある。
#   1) OAuth：認可画面のURLを作り、返ってきた code を長期トークン（60日）に交換する（クラスメソッド）
#   2) 検索：keyword_search で公開投稿を探す（インスタンスメソッド）
# 投稿者の username は fields に入れない（保存も表示もしないため）。
module Sources
  class ThreadsSource
    # 認可画面は threads.com、API は graph.threads.net（Metaの公式ドキュメントどおり）
    AUTHORIZE_URL = "https://threads.com/oauth/authorize".freeze
    GRAPH_HOST = "https://graph.threads.net".freeze

    # 必要最小限の権限だけ求める。keyword_search にはアプリ審査が必要
    SCOPES = %w[threads_basic threads_keyword_search].freeze

    # 取得する項目。username（投稿者名）は取らない
    FIELDS = %w[id text timestamp permalink media_type].freeze

    DEFAULT_REDIRECT_URI = "https://voc-1ntn.onrender.com/threads/callback".freeze
    DEFAULT_LIMIT = 25
    MAX_LIMIT = 100

    class ConfigurationError < StandardError; end
    class ApiError < StandardError; end

    class << self
      def app_id
        ENV["THREADS_APP_ID"]
      end

      def app_secret
        ENV["THREADS_APP_SECRET"]
      end

      def redirect_uri
        ENV["THREADS_REDIRECT_URI"].presence || DEFAULT_REDIRECT_URI
      end

      def configured?
        app_id.present? && app_secret.present?
      end

      # 1) ユーザーを送る認可画面のURL。state はCSRF対策で呼び出し側が作って渡す
      def authorize_url(state:)
        ensure_configured!

        params = {
          client_id: app_id,
          redirect_uri: redirect_uri,
          scope: SCOPES.join(","),
          response_type: "code",
          state: state
        }
        "#{AUTHORIZE_URL}?#{params.to_query}"
      end

      # 2) 認可後に返ってきた code を、短期トークン→長期トークン（60日）に交換する。
      # 戻り値は { "access_token" =>, "user_id" =>, "expires_in" => }
      def exchange_code(code:, connection: nil)
        ensure_configured!
        connection ||= build_connection

        short = connection.post("/oauth/access_token", {
          client_id: app_id,
          client_secret: app_secret,
          code: code,
          grant_type: "authorization_code",
          redirect_uri: redirect_uri
        }).body
        raise ApiError, "短期トークンを取得できませんでした" if short["access_token"].blank?

        long = connection.get("/access_token", {
          grant_type: "th_exchange_token",
          client_secret: app_secret,
          access_token: short["access_token"]
        }).body
        raise ApiError, "長期トークンに交換できませんでした" if long["access_token"].blank?

        long.merge("user_id" => short["user_id"])
      end

      def build_connection
        Faraday.new(url: GRAPH_HOST) do |f|
          f.request :url_encoded
          f.response :json
          f.response :raise_error
          f.options.timeout = 30
        end
      end

      private

      def ensure_configured!
        return if configured?

        raise ConfigurationError, "THREADS_APP_ID / THREADS_APP_SECRET が設定されていません（.env とRenderの環境変数を確認）"
      end
    end

    def initialize(access_token:, connection: nil, logger: Rails.logger)
      @access_token = access_token
      @connection = connection || self.class.build_connection
      @logger = logger
    end

    # 検索語で公開投稿を探す。戻り値は API の投稿の配列（保存はしない）。
    # days を渡すと、その日数ぶんに絞る
    def search(query, limit: DEFAULT_LIMIT, days: nil, search_type: "RECENT")
      params = {
        q: query,
        search_type: search_type,
        fields: FIELDS.join(","),
        limit: limit.clamp(1, MAX_LIMIT),
        access_token: @access_token
      }
      params[:since] = days.days.ago.to_i if days

      body = @connection.get("/v1.0/keyword_search", params).body
      posts = Array(body["data"])
      log "検索 q=#{query} → #{posts.size}件"
      posts
    rescue Faraday::Error => e
      # 権限が無い・トークンが切れた場合はここに来る。本文をそのまま見せると原因が分かる
      raise ApiError, "Threadsの検索に失敗しました（#{e.response&.dig(:status)}）: #{e.response&.dig(:body)}"
    end

    private

    def log(message)
      @logger.info "[threads] #{message}"
    end
  end
end
