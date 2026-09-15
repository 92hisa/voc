require "test_helper"

class SubscriberTest < ActiveSupport::TestCase
  test "メールアドレスは小文字に正規化される" do
    subscriber = Subscriber.create!(email: " Reader2@Example.com ", audience: audiences(:web_seisaku))
    assert_equal "reader2@example.com", subscriber.email
  end

  test "同じオーディエンスに同じメールアドレスは登録できない" do
    duplicate = Subscriber.new(email: "READER@example.com", audience: audiences(:web_seisaku))
    assert_not duplicate.valid?
  end

  test "別のオーディエンスなら同じメールアドレスを登録できる" do
    subscriber = Subscriber.new(email: "reader@example.com", audience: audiences(:ec_unei))
    assert subscriber.valid?
  end

  test "active は購読中の人だけを返す" do
    assert_includes Subscriber.active, subscribers(:confirmed)
    assert_not_includes Subscriber.active, subscribers(:unsubscribed)
  end
end
