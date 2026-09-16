# このファイルは Threads連携画面のテスト。Threadsへの通信はしない（sourceを差し替える）。
require "test_helper"

class ThreadsControllerTest < ActionDispatch::IntegrationTest
  # Threadsへ通信しない差し替え。stub_const（Rails標準）で Sources::ThreadsSource の代わりに使う。
  # 例外クラスは本物と同じものを指すので、コントローラの rescue もそのまま効く
  class FakeThreadsSource
    # 差し替え前の本物。URL作りは本物に任せる（差し替え後に名前で呼ぶと自分を呼んで無限ループになる）
    REAL = Sources::ThreadsSource

    ApiError = Sources::ThreadsSource::ApiError
    ConfigurationError = Sources::ThreadsSource::ConfigurationError
    SCOPES = Sources::ThreadsSource::SCOPES

    Instance = Struct.new(:posts, :error) do
      def search(_query, **_options)
        raise ApiError, error if error

        posts
      end
    end

    class << self
      attr_accessor :posts, :error

      def new(**)
        Instance.new(posts || [], error)
      end

      def exchange_code(**)
        { "access_token" => "long-token", "user_id" => 42, "expires_in" => 5_183_944 }
      end

      def configured?
        true
      end

      def redirect_uri
        REAL.redirect_uri
      end

      def authorize_url(state:)
        REAL.authorize_url(state: state)
      end
    end
  end

  setup do
    ENV["THREADS_APP_ID"] = "1234567890"
    ENV["THREADS_APP_SECRET"] = "test-secret"
    ENV["THREADS_REDIRECT_URI"] = "https://voc.onrender.com/threads/callback"
  end

  teardown do
    FakeThreadsSource.posts = nil
    FakeThreadsSource.error = nil
    ENV.delete("THREADS_APP_ID")
    ENV.delete("THREADS_APP_SECRET")
    ENV.delete("THREADS_REDIRECT_URI")
  end

  test "ログイン画面に権限の説明とボタンが出る" do
    get threads_login_url

    assert_response :success
    assert_select "h1", "Threadsと連携する"
    assert_match "threads_keyword_search", response.body
    assert_match "https://voc.onrender.com/threads/callback", response.body
    assert_select "form[action=?]", threads_authorize_path
  end

  test "App IDが無いときはボタンを出さず理由を書く" do
    ENV.delete("THREADS_APP_ID")

    get threads_login_url

    assert_response :success
    assert_select "form[action=?]", threads_authorize_path, count: 0
    assert_match "THREADS_APP_ID", response.body
  end

  test "ログインを押すとThreadsの認可画面へ送る" do
    post threads_authorize_url

    assert_response :redirect
    assert_match "https://threads.com/oauth/authorize", response.location
    assert_match "scope=threads_basic%2Cthreads_keyword_search", response.location
  end

  test "stateが一致しないコールバックは受け付けない" do
    get threads_callback_url(code: "the-code", state: "wrong")

    assert_redirected_to threads_login_path
    assert_match "state", flash[:alert]
  end

  test "許可しなかったときはログイン画面に戻す" do
    get threads_callback_url(error: "access_denied", error_description: "ユーザーが拒否しました")

    assert_redirected_to threads_login_path
    assert_match "キャンセル", flash[:alert]
  end

  test "ログインしていなければ検索画面は見られない" do
    get threads_search_url

    assert_redirected_to threads_login_path
  end

  test "検索画面はオーディエンスの検索語で投稿を一覧表示する" do
    query = audience_queries(:web_threads)
    FakeThreadsSource.posts = [ { "id" => "1", "text" => "ホームページを作りたいけど相場が分からない",
                                  "timestamp" => "2026-09-15T10:00:00+0000", "permalink" => "https://www.threads.com/@x/post/1" } ]

    stub_const(Sources, :ThreadsSource, FakeThreadsSource) do
      log_in
      get threads_search_url(audience_slug: query.audience.slug, query: query.query)
    end

    assert_response :success
    assert_match "ホームページを作りたいけど相場が分からない", response.body
    assert_select "a[href=?]", "https://www.threads.com/@x/post/1"
    # 投稿者名は画面に出さない
    assert_no_match(/@x<|アカウント名：/, response.body)
  end

  test "取得に失敗したら理由を画面に出す" do
    query = audience_queries(:web_threads)
    FakeThreadsSource.error = "Threadsの検索に失敗しました（400）"

    stub_const(Sources, :ThreadsSource, FakeThreadsSource) do
      log_in
      get threads_search_url(audience_slug: query.audience.slug, query: query.query)
    end

    assert_response :success
    assert_match "投稿を取得できませんでした", response.body
    assert_match "アプリ審査が必要な権限です", response.body
  end

  private

  # 認可画面からコールバックまでを通して、セッションにトークンが入った状態を作る
  def log_in
    post threads_authorize_url
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]
    get threads_callback_url(code: "the-code", state: state)
  end
end
