require "test_helper"

class AudienceTest < ActiveSupport::TestCase
  test "slug は一意" do
    duplicate = Audience.new(slug: audiences(:web_seisaku).slug, name: "別の名前")
    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :slug
  end

  test "slug は英小文字・数字・ハイフンのみ" do
    assert_not Audience.new(slug: "Web制作", name: "テスト").valid?
    assert Audience.new(slug: "web-seisaku-2", name: "テスト").valid?
  end

  test "to_param は slug を返す" do
    assert_equal "web-seisaku", audiences(:web_seisaku).to_param
  end
end
