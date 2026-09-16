# このファイルは規約系4ページが表示できることと、方針の要点が載っていることを確かめる。
require "test_helper"

class LegalControllerTest < ActionDispatch::IntegrationTest
  test "トップページが表示できる" do
    get root_url

    assert_response :success
    assert_select "h1", LegalHelper::SERVICE_NAME
    # どのページからも3ページに行ける（審査でリンク切れがないこと）
    assert_select "footer a[href=?]", privacy_path
    assert_select "footer a[href=?]", terms_path
    assert_select "footer a[href=?]", data_deletion_path
  end

  test "プライバシーポリシーに保存範囲と保持期間が書いてある" do
    get privacy_url

    assert_response :success
    assert_select "h1", "プライバシーポリシー"
    assert_match "投稿者の氏名・アカウント名・アイコン・プロフィールは保存も表示もしません", response.body
    assert_match "最大#{LegalHelper::RETENTION_DAYS}日", response.body
    assert_match "営業リストの作成・提供・販売も行いません", response.body
  end

  test "利用規約に免責と管轄が書いてある" do
    get terms_url

    assert_response :success
    assert_select "h1", "利用規約"
    assert_match "正確性・完全性・最新性を保証しません", response.body
    assert_match "専属的合意管轄", response.body
  end

  test "データ削除の手順に連絡先と自動削除が書いてある" do
    get data_deletion_url

    assert_response :success
    assert_select "h1", "データ削除の手順"
    assert_match "30日以内", response.body
    assert_match "ウェブサイトの許可", response.body
  end

  test "運営者名と連絡先は環境変数から出す" do
    with_env("OPERATOR_NAME" => "テスト運営者", "CONTACT_EMAIL" => "test@example.com") do
      get privacy_url
    end

    assert_match "テスト運営者", response.body
    assert_select "a[href=?]", "mailto:test@example.com?subject=%E3%83%97%E3%83%A9%E3%82%A4%E3%83%90%E3%82%B7%E3%83%BC%E3%83%9D%E3%83%AA%E3%82%B7%E3%83%BC%E3%81%AB%E3%81%A4%E3%81%84%E3%81%A6"
  end

  test "運営者名が未設定なら設定を促す文字を出す" do
    with_env("OPERATOR_NAME" => nil, "CONTACT_EMAIL" => nil) do
      get terms_url
    end

    assert_match "OPERATOR_NAME を設定してください", response.body
  end

  private

  # 環境変数を一時的に差し替える（開発者の .env の値でテストが揺れないように）
  def with_env(values)
    original = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
