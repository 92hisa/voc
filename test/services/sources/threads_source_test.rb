# このファイルは ThreadsSource のテスト。Faraday のテストアダプタで応答を差し込み、通信はしない。
require "test_helper"

class Sources::ThreadsSourceTest < ActiveSupport::TestCase
  setup do
    ENV["THREADS_APP_ID"] = "1234567890"
    ENV["THREADS_APP_SECRET"] = "test-secret"
    ENV["THREADS_REDIRECT_URI"] = "https://voc.onrender.com/threads/callback"
  end

  teardown do
    ENV.delete("THREADS_APP_ID")
    ENV.delete("THREADS_APP_SECRET")
    ENV.delete("THREADS_REDIRECT_URI")
  end

  def build_connection(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    connection = Faraday.new do |f|
      f.request :url_encoded
      f.response :json
      f.response :raise_error
      f.adapter :test, stubs
    end
    [ connection, stubs ]
  end

  def json(body)
    [ 200, { "Content-Type" => "application/json" }, body.to_json ]
  end

  test "認可画面のURLに必要なパラメータが入る" do
    url = Sources::ThreadsSource.authorize_url(state: "abc123")

    assert url.start_with?("https://threads.com/oauth/authorize?")
    params = Rack::Utils.parse_query(URI.parse(url).query)
    assert_equal "1234567890", params["client_id"]
    assert_equal "https://voc.onrender.com/threads/callback", params["redirect_uri"]
    assert_equal "code", params["response_type"]
    assert_equal "abc123", params["state"]
    # 求める権限は必要最小限の2つだけ
    assert_equal "threads_basic,threads_keyword_search", params["scope"]
  end

  test "App IDが無いときは認可URLを作らない" do
    ENV.delete("THREADS_APP_ID")

    assert_not Sources::ThreadsSource.configured?
    error = assert_raises(Sources::ThreadsSource::ConfigurationError) { Sources::ThreadsSource.authorize_url(state: "x") }
    assert_match "THREADS_APP_ID", error.message
  end

  test "codeを短期トークン経由で長期トークンに交換する" do
    connection, = build_connection do |stub|
      stub.post("/oauth/access_token") { json("access_token" => "short-token", "user_id" => 42) }
      stub.get("/access_token") { json("access_token" => "long-token", "token_type" => "bearer", "expires_in" => 5_183_944) }
    end

    token = Sources::ThreadsSource.exchange_code(code: "the-code", connection: connection)

    assert_equal "long-token", token["access_token"]
    assert_equal 42, token["user_id"]
    assert_equal 5_183_944, token["expires_in"]
  end

  test "長期トークンに交換できなければ落とす" do
    connection, = build_connection do |stub|
      stub.post("/oauth/access_token") { json("access_token" => "short-token", "user_id" => 42) }
      stub.get("/access_token") { json("error" => { "message" => "invalid" }) }
    end

    error = assert_raises(Sources::ThreadsSource::ApiError) { Sources::ThreadsSource.exchange_code(code: "the-code", connection: connection) }
    assert_match "長期トークン", error.message
  end

  test "検索は本文・日時・リンクだけを取りに行き、投稿者名は取らない" do
    request = nil
    connection, = build_connection do |stub|
      stub.get("/v1.0/keyword_search") do |env|
        request = env
        json("data" => [
          { "id" => "1", "text" => "ホームページを作りたい", "timestamp" => "2026-09-15T10:00:00+0000", "permalink" => "https://www.threads.com/@x/post/1" }
        ])
      end
    end

    posts = Sources::ThreadsSource.new(access_token: "long-token", connection: connection, logger: ActiveSupport::Logger.new(IO::NULL))
      .search("ホームページ 作りたい", days: 7)

    assert_equal 1, posts.size
    assert_equal "ホームページを作りたい", posts.first["text"]

    params = request.params
    assert_equal "ホームページ 作りたい", params["q"]
    assert_equal "RECENT", params["search_type"]
    assert_equal "id,text,timestamp,permalink,media_type", params["fields"]
    assert_not_includes params["fields"], "username"
    assert params["since"].present?
  end

  test "権限が無いときは分かるエラーにする" do
    connection, = build_connection do |stub|
      stub.get("/v1.0/keyword_search") { [ 400, { "Content-Type" => "application/json" }, { "error" => { "message" => "permission" } }.to_json ] }
    end

    source = Sources::ThreadsSource.new(access_token: "long-token", connection: connection, logger: ActiveSupport::Logger.new(IO::NULL))
    error = assert_raises(Sources::ThreadsSource::ApiError) { source.search("ホームページ 作りたい") }
    assert_match "400", error.message
  end
end
