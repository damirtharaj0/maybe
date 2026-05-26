require "test_helper"

class LayoutThemeTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "data-theme attribute matches resolved_theme cookie when present" do
    cookies[:resolved_theme] = "dark"
    get root_path
    assert_response :success
    assert_select "html[data-theme='dark']"
  end

  test "data-theme attribute defaults to 'light' when resolved_theme cookie is absent" do
    cookies.delete(:resolved_theme)
    get root_path
    assert_response :success
    assert_select "html[data-theme='light']"
  end
end
