require "test_helper"

class Provider::YahooFinanceTest < ActiveSupport::TestCase
  include SecurityProviderInterfaceTest

  setup do
    @subject = Provider::YahooFinance.new
  end

  # Override the Synth-specific count assertion (Yahoo returns variable count, not exactly 147)
  undef_method :test_fetches_paginated_securities_prices
  define_method :test_fetches_paginated_securities_prices do
    aapl = securities(:aapl)

    VCR.use_cassette("yahoo_finance/security_prices") do
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

  # Override because Yahoo Finance doesn't provide logo_url
  undef_method :test_fetches_security_info
  define_method :test_fetches_security_info do
    aapl = securities(:aapl)

    VCR.use_cassette("yahoo_finance/security_info") do
      response = @subject.fetch_security_info(
        symbol: aapl.ticker,
        exchange_operating_mic: aapl.exchange_operating_mic
      )

      info = response.data

      assert_equal "AAPL", info.symbol
      assert_equal "Apple Inc.", info.name
      assert_equal "common stock", info.kind
      assert info.description.present?
    end
  end
end
