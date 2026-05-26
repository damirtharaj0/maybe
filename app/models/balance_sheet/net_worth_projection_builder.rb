class BalanceSheet::NetWorthProjectionBuilder
  LOOKBACK_MONTHS = 12

  DAILY   = :daily
  WEEKLY  = :weekly
  MONTHLY = :monthly

  def initialize(family)
    @family = family
  end

  def net_worth_projection_series(current_net_worth:, period: Period.last_365_days)
    duration_days = (period.end_date - period.start_date).to_i
    granularity, step_count = projection_granularity(duration_days)
    delta = scaled_delta(granularity)

    today = Date.current
    values = step_count.times.map do |i|
      date = step_date(today, granularity, i)
      projected_value = current_net_worth + (delta * i)
      prev_value = current_net_worth + (delta * (i - 1))

      Series::Value.new(
        date: date,
        date_formatted: I18n.l(date, format: :long),
        value: projected_value,
        trend: Trend.new(
          current: projected_value,
          previous: i == 0 ? nil : prev_value
        )
      )
    end

    Series.new(
      start_date: today,
      end_date: step_date(today, granularity, step_count - 1),
      interval: interval_label(granularity),
      values: values,
      favorable_direction: "up",
      projected_start_date: today,
      months_of_data: months_of_data
    )
  end

  private
    attr_reader :family

    def projection_granularity(duration_days)
      if duration_days <= 30
        [ DAILY, duration_days ]
      elsif duration_days <= 180
        [ WEEKLY, (duration_days / 7.0).ceil ]
      else
        [ MONTHLY, (duration_days / 30.44).ceil ]
      end
    end

    def scaled_delta(granularity)
      monthly = median_income - avg_expense
      case granularity
      when DAILY  then monthly / 30.44
      when WEEKLY then monthly / 4.348
      else             monthly
      end
    end

    def step_date(today, granularity, i)
      case granularity
      when DAILY  then today + i
      when WEEKLY then today + (i * 7)
      else             today >> i
      end
    end

    def interval_label(granularity)
      case granularity
      when DAILY  then "1 day"
      when WEEKLY then "1 week"
      else             "1 month"
      end
    end

    def scoped_transactions
      @scoped_transactions ||= family.transactions
        .visible
        .in_period(Period.custom(start_date: LOOKBACK_MONTHS.months.ago.to_date, end_date: Date.current))
    end

    def stats
      @stats ||= scoped_family_stats
    end

    def median_income
      stats.find { |s| s.classification == "income" }&.median || 0
    end

    def avg_expense
      stats.find { |s| s.classification == "expense" }&.avg || 0
    end

    def scoped_family_stats
      ActiveRecord::Base.connection.select_all(scoped_stats_sql).map do |row|
        StatRow.new(
          classification: row["classification"],
          median: row["median"],
          avg: row["avg"]
        )
      end
    end

    StatRow = Data.define(:classification, :median, :avg)

    def scoped_stats_sql
      ActiveRecord::Base.sanitize_sql_array([
        stats_query_sql(scoped_transactions.to_sql),
        { target_currency: family.currency }
      ])
    end

    def stats_query_sql(transactions_subquery)
      <<~SQL
        WITH period_totals AS (
          SELECT
            date_trunc('month', ae.date) as period,
            CASE WHEN ae.amount < 0 THEN 'income' ELSE 'expense' END as classification,
            SUM(ae.amount * COALESCE(er.rate, 1)) as total
          FROM (#{transactions_subquery}) t
          JOIN entries ae ON ae.entryable_id = t.id AND ae.entryable_type = 'Transaction'
          LEFT JOIN exchange_rates er ON (
            er.date = ae.date AND
            er.from_currency = ae.currency AND
            er.to_currency = :target_currency
          )
          WHERE t.kind NOT IN ('funds_movement', 'one_time', 'cc_payment')
            AND ae.excluded = false
          GROUP BY period, CASE WHEN ae.amount < 0 THEN 'income' ELSE 'expense' END
        )
        SELECT
          classification,
          ABS(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total)) as median,
          ABS(AVG(total)) as avg
        FROM period_totals
        GROUP BY classification;
      SQL
    end

    def months_of_data
      @months_of_data ||= begin
        earliest_date_sql = <<~SQL
          SELECT MIN(ae.date)
          FROM (#{scoped_transactions.to_sql}) t
          JOIN entries ae ON ae.entryable_id = t.id AND ae.entryable_type = 'Transaction'
          WHERE t.kind NOT IN ('funds_movement', 'one_time', 'cc_payment')
            AND ae.excluded = false
        SQL
        earliest = ActiveRecord::Base.connection.select_value(earliest_date_sql)
        return 0 if earliest.nil?
        earliest = earliest.to_date
        ((Date.current.year * 12 + Date.current.month) - (earliest.year * 12 + earliest.month)).clamp(0, 12)
      end
    end
end
