# このファイルは規約ページに出す運営者名・問い合わせ先・改定日を返す。
# 運営者名とメールは環境変数（OPERATOR_NAME / CONTACT_EMAIL）から読む。
module LegalHelper
  SERVICE_NAME = "お客さんの声リサーチ".freeze

  # 規約・プライバシーポリシーの最終改定日。内容を直したらここも直す
  LAST_UPDATED_ON = "2026年9月16日".freeze

  # 投稿本文の保持期間（app/services/sources/*_source.rb の RETENTION_DAYS と合わせる）
  RETENTION_DAYS = 30

  def service_name
    SERVICE_NAME
  end

  def operator_name
    ENV["OPERATOR_NAME"].presence || "（環境変数 OPERATOR_NAME を設定してください）"
  end

  def contact_email
    ENV["CONTACT_EMAIL"].presence || "（環境変数 CONTACT_EMAIL を設定してください）"
  end

  def contact_mail_link(subject)
    email = ENV["CONTACT_EMAIL"].presence
    return tag.span(contact_email) if email.nil?

    mail_to email, email, subject: subject, class: "underline hover:text-gray-900"
  end

  def last_updated_on
    LAST_UPDATED_ON
  end

  def retention_days
    RETENTION_DAYS
  end
end
