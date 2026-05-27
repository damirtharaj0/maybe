class Provider::YahooFinance < Provider
  include SecurityConcept

  Error = Class.new(Provider::Error)

  EXCHANGE_MIC_SUFFIX_MAP = {
    # US exchanges — no suffix
    "XNYS" => "",
    "XNAS" => "",
    "XASE" => "",
    "BATS" => "",
    # London Stock Exchange
    "XLON" => ".L",
    # Deutsche Börse (Frankfurt)
    "XETR" => ".DE",
    # Tokyo Stock Exchange
    "XTKS" => ".T",
    # Toronto Stock Exchange
    "XTSE" => ".TO",
    # Australian Securities Exchange
    "XASX" => ".AX",
    # Hong Kong Stock Exchange
    "XHKG" => ".HK",
    # Shanghai Stock Exchange
    "XSHG" => ".SS",
    # Shenzhen Stock Exchange
    "XSHE" => ".SZ",
    # Euronext Paris
    "XPAR" => ".PA",
    # Euronext Amsterdam
    "XAMS" => ".AS",
    # SIX Swiss Exchange
    "XSWX" => ".SW",
    # Borsa Italiana (Milan)
    "XMIL" => ".MI",
    # Bolsa de Madrid
    "XMAD" => ".MC",
    # Korea Exchange
    "XKRX" => ".KS",
    # Bombay Stock Exchange
    "XBOM" => ".BO",
    # National Stock Exchange of India
    "XNSE" => ".NS"
  }.freeze

  def search_securities(symbol, country_code: nil, exchange_operating_mic: nil)
    raise NotImplementedError, "Provider::YahooFinance does not implement #search_securities yet"
  end

  def fetch_security_info(symbol:, exchange_operating_mic:)
    raise NotImplementedError, "Provider::YahooFinance does not implement #fetch_security_info yet"
  end

  def fetch_security_price(symbol:, exchange_operating_mic:, date:)
    raise NotImplementedError, "Provider::YahooFinance does not implement #fetch_security_price yet"
  end

  def fetch_security_prices(symbol:, exchange_operating_mic:, start_date:, end_date:)
    raise NotImplementedError, "Provider::YahooFinance does not implement #fetch_security_prices yet"
  end

  private
    def ticker_for(symbol, exchange_operating_mic)
      if EXCHANGE_MIC_SUFFIX_MAP.key?(exchange_operating_mic)
        "#{symbol}#{EXCHANGE_MIC_SUFFIX_MAP[exchange_operating_mic]}"
      else
        Rails.logger.warn("Provider::YahooFinance: unknown exchange MIC '#{exchange_operating_mic}' for symbol '#{symbol}', falling back to bare symbol")
        symbol
      end
    end

    def client
      @client ||= Faraday.new(url: "https://query1.finance.yahoo.com") do |faraday|
        faraday.request(:retry, {
          max: 2,
          interval: 0.05,
          interval_randomness: 0.5,
          backoff_factor: 2
        })

        faraday.response :raise_error
        faraday.headers["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      end
    end
end
