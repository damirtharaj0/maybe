require "test_helper"

class Provider::RegistryTest < ActiveSupport::TestCase
  test "synth configured with ENV" do
    Setting.stubs(:synth_api_key).returns(nil)

    with_env_overrides SYNTH_API_KEY: "123" do
      assert_instance_of Provider::Synth, Provider::Registry.get_provider(:synth)
    end
  end

  test "synth configured with Setting" do
    Setting.stubs(:synth_api_key).returns("123")

    with_env_overrides SYNTH_API_KEY: nil do
      assert_instance_of Provider::Synth, Provider::Registry.get_provider(:synth)
    end
  end

  test "synth not configured" do
    Setting.stubs(:synth_api_key).returns(nil)

    with_env_overrides SYNTH_API_KEY: nil do
      assert_nil Provider::Registry.get_provider(:synth)
    end
  end

  test "securities concept uses twelve data when synth key is absent" do
    Setting.stubs(:synth_api_key).returns(nil)
    Setting.stubs(:twelve_data_api_key).returns(nil)

    with_env_overrides SYNTH_API_KEY: nil, TWELVE_DATA_API_KEY: "td_key" do
      assert_instance_of Provider::TwelveData, Provider::Registry.for_concept(:securities).providers.first
    end
  end

  test "securities concept uses synth when synth key is present" do
    Setting.stubs(:synth_api_key).returns(nil)
    Setting.stubs(:twelve_data_api_key).returns(nil)

    with_env_overrides SYNTH_API_KEY: "test_key", TWELVE_DATA_API_KEY: nil do
      assert_instance_of Provider::Synth, Provider::Registry.for_concept(:securities).providers.first
    end
  end

  test "securities concept has no provider when no keys configured" do
    Setting.stubs(:synth_api_key).returns(nil)
    Setting.stubs(:twelve_data_api_key).returns(nil)

    with_env_overrides SYNTH_API_KEY: nil, TWELVE_DATA_API_KEY: nil do
      assert_empty Provider::Registry.for_concept(:securities).providers
    end
  end
end
