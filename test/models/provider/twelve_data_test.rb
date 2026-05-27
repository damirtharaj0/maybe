require "test_helper"

class Provider::TwelveDataTest < ActiveSupport::TestCase
  include SecurityProviderInterfaceTest

  setup do
    ENV["TWELVE_DATA_API_KEY"] ||= "test_key"
    @subject = Provider::TwelveData.new(ENV["TWELVE_DATA_API_KEY"])
  end

  # Override: Twelve Data returns a different count than Synth's fixed 147
  undef_method :test_fetches_paginated_securities_prices
  define_method :test_fetches_paginated_securities_prices do
    aapl = securities(:aapl)

    VCR.use_cassette("twelve_data/security_prices") do
      response = @subject.fetch_security_prices(
        symbol: aapl.ticker,
        exchange_operating_mic: aapl.exchange_operating_mic,
        start_date: Date.iso8601("2024-01-01"),
        end_date: Date.iso8601("2024-08-01")
      )

      assert response.success?
      assert response.data.first.date.is_a?(Date)
      assert response.data.count > 0
    end
  end
end
