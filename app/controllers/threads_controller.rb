# このファイルはThreadsにログインして、オーディエンスの検索語で投稿を一覧表示する画面。
# 流れは3つ：① /threads/login（説明）→ ② Threadsの認可画面 → ③ /threads/search（一覧）。
# アプリ審査の録画用に、この1本の流れだけを見せる。取得した投稿はDBに保存しない。
class ThreadsController < ApplicationController
  before_action :require_token, only: :search

  # ① ログインの説明（ここから始める）
  def login
    @configured = Sources::ThreadsSource.configured?
    @redirect_uri = Sources::ThreadsSource.redirect_uri
    @scopes = Sources::ThreadsSource::SCOPES
    @logged_in = access_token.present?
  end

  # ボタンを押したらThreadsの認可画面へ送る（state はCSRF対策）
  def authorize
    state = SecureRandom.hex(16)
    session[:threads_oauth_state] = state

    redirect_to Sources::ThreadsSource.authorize_url(state: state), allow_other_host: true
  rescue Sources::ThreadsSource::ConfigurationError => e
    redirect_to threads_login_path, alert: e.message
  end

  # ② 認可画面から戻ってくる先。code を長期トークンに交換してセッションに持つ
  def callback
    if params[:error].present?
      # ユーザーが「許可しない」を押した場合など
      return redirect_to threads_login_path, alert: "Threadsの連携をキャンセルしました（#{params[:error_description] || params[:error]}）"
    end

    expected = session.delete(:threads_oauth_state)
    return redirect_to threads_login_path, alert: "stateが一致しません。最初からやり直してください。" if expected.blank? || expected != params[:state]

    token = Sources::ThreadsSource.exchange_code(code: params[:code])
    session[:threads_access_token] = token["access_token"]
    session[:threads_user_id] = token["user_id"]
    session[:threads_token_expires_at] = token["expires_in"].to_i.seconds.from_now.iso8601

    redirect_to threads_search_path, notice: "Threadsと連携しました。検索語を選んで投稿を表示できます。"
  rescue Sources::ThreadsSource::ApiError, Faraday::Error => e
    redirect_to threads_login_path, alert: "トークンの取得に失敗しました：#{e.message}"
  end

  # ③ オーディエンスの検索語で投稿を一覧表示する
  def search
    @audiences = Audience.order(:id)
    @audience = params[:audience_slug].present? ? Audience.find_by(slug: params[:audience_slug]) : @audiences.first
    @queries = @audience ? @audience.audience_queries.for_source("threads").active.order(:query) : AudienceQuery.none
    # オーディエンスを切り替えたときに、前の検索語が残らないようにする
    @query = params[:query].presence_in(@queries.pluck(:query)) || @queries.first&.query

    return if @query.blank?

    @posts = Sources::ThreadsSource.new(access_token: access_token).search(@query, days: 7)
  rescue Sources::ThreadsSource::ApiError => e
    @error = e.message
  end

  # 連携を切る（セッションのトークンを捨てるだけ）
  def logout
    session.delete(:threads_access_token)
    session.delete(:threads_user_id)
    session.delete(:threads_token_expires_at)

    redirect_to threads_login_path, notice: "Threadsの連携を解除しました。"
  end

  private

  def access_token
    session[:threads_access_token]
  end

  def require_token
    redirect_to threads_login_path, alert: "先にThreadsでログインしてください。" if access_token.blank?
  end
end
