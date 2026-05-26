require "test_helper"

class BalanceSheet::NetWorthProjectionBuilderTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(
      name: "Checking",
      currency: "USD",
      balance: 10_000,
      accountable: Depository.new
    )
  end

  test "returns 12 monthly values for a 365-day period" do
    create_income_and_expense_transactions

    builder = BalanceSheet::NetWorthProjectionBuilder.new(@family)
    series = builder.net_worth_projection_series(current_net_worth: 10_000, period: Period.last_365_days)

    assert_instance_of Series, series
    assert_equal 12, series.values.length
  end

  test "returns daily values for a 30-day period" do
    create_income_and_expense_transactions

    builder = BalanceSheet::NetWorthProjectionBuilder.new(@family)
    series = builder.net_worth_projection_series(current_net_worth: 10_000, period: Period.last_30_days)

    assert_equal 30, series.values.length
    assert_equal Date.current + 1, series.values[1].date
  end

  test "returns weekly values for a 90-day period" do
    create_income_and_expense_transactions

    builder = BalanceSheet::NetWorthProjectionBuilder.new(@family)
    series = builder.net_worth_projection_series(current_net_worth: 10_000, period: Period.last_90_days)

    assert_equal 13, series.values.length
    assert_equal Date.current + 7, series.values[1].date
  end

  test "first projected value equals current net worth" do
    create_income_and_expense_transactions

    builder = BalanceSheet::NetWorthProjectionBuilder.new(@family)
    series = builder.net_worth_projection_series(current_net_worth: 10_000, period: Period.last_365_days)

    assert_equal 10_000, series.values.first.value
  end

  test "projected values increment by median_income minus avg_expense each month" do
    # Create transactions spread across 3 different months so stats are meaningful
    create_transaction(account: @account, amount: -3_000, date: 3.months.ago.to_date) # income
    create_transaction(account: @account, amount: -3_000, date: 2.months.ago.to_date) # income
    create_transaction(account: @account, amount: -3_000, date: 1.month.ago.to_date)  # income
    create_transaction(account: @account, amount: 1_000, date: 3.months.ago.to_date)  # expense
    create_transaction(account: @account, amount: 1_000, date: 2.months.ago.to_date)  # expense
    create_transaction(account: @account, amount: 1_000, date: 1.month.ago.to_date)   # expense

    builder = BalanceSheet::NetWorthProjectionBuilder.new(@family)
    series = builder.net_worth_projection_series(current_net_worth: 10_000, period: Period.last_365_days)

    # With income of 3000/month and expense of 1000/month, delta = 2000
    expected_delta = 3_000.0 - 1_000.0
    assert_in_delta 10_000 + expected_delta, series.values[1].value, 1.0
    assert_in_delta 10_000 + (expected_delta * 2), series.values[2].value, 1.0
    assert_in_delta 10_000 + (expected_delta * 11), series.values[11].value, 1.0
  end

  test "negative savings rate produces a strictly declining series" do
    # Expenses exceed income: expense 2000/month, income 500/month => delta = -1500
    create_transaction(account: @account, amount: 2_000, date: 3.months.ago.to_date)  # expense
    create_transaction(account: @account, amount: 2_000, date: 2.months.ago.to_date)  # expense
    create_transaction(account: @account, amount: 2_000, date: 1.month.ago.to_date)   # expense
    create_transaction(account: @account, amount: -500, date: 3.months.ago.to_date)   # income
    create_transaction(account: @account, amount: -500, date: 2.months.ago.to_date)   # income
    create_transaction(account: @account, amount: -500, date: 1.month.ago.to_date)    # income

    builder = BalanceSheet::NetWorthProjectionBuilder.new(@family)
    series = builder.net_worth_projection_series(current_net_worth: 10_000, period: Period.last_365_days)

    series.values.each_cons(2) do |prev, curr|
      assert curr.value < prev.value, "Expected #{curr.value} to be less than #{prev.value}"
    end
  end

  test "projected_start_date on returned series is set to today" do
    create_income_and_expense_transactions

    builder = BalanceSheet::NetWorthProjectionBuilder.new(@family)
    series = builder.net_worth_projection_series(current_net_worth: 10_000, period: Period.last_365_days)

    assert_equal Date.current, series.projected_start_date
  end

  test "months_of_data is reported correctly when fewer than 12 months of transactions exist" do
    # Only create 2 months of data
    create_transaction(account: @account, amount: -1_000, date: 2.months.ago.to_date)
    create_transaction(account: @account, amount: 500, date: 1.month.ago.to_date)

    builder = BalanceSheet::NetWorthProjectionBuilder.new(@family)
    series = builder.net_worth_projection_series(current_net_worth: 5_000, period: Period.last_365_days)

    assert series.months_of_data <= 12
    assert series.months_of_data >= 1
  end

  test "projection is still returned when fewer than 12 months of transactions exist" do
    create_transaction(account: @account, amount: -1_000, date: 1.month.ago.to_date)

    builder = BalanceSheet::NetWorthProjectionBuilder.new(@family)
    series = builder.net_worth_projection_series(current_net_worth: 5_000, period: Period.last_365_days)

    assert_instance_of Series, series
    assert_equal 12, series.values.length
  end

  test "months_of_data is 0 when family has no transaction history" do
    builder = BalanceSheet::NetWorthProjectionBuilder.new(@family)
    series = builder.net_worth_projection_series(current_net_worth: 0, period: Period.last_365_days)

    assert_equal 0, series.months_of_data
  end

  test "returns flat series when no transaction history exists" do
    builder = BalanceSheet::NetWorthProjectionBuilder.new(@family)
    series = builder.net_worth_projection_series(current_net_worth: 5_000, period: Period.last_365_days)

    assert_equal 12, series.values.length
    series.values.each do |v|
      assert_equal 5_000, v.value
    end
  end

  private
    def create_income_and_expense_transactions
      create_transaction(account: @account, amount: -2_000, date: 3.months.ago.to_date) # income
      create_transaction(account: @account, amount: -2_000, date: 2.months.ago.to_date) # income
      create_transaction(account: @account, amount: -2_000, date: 1.month.ago.to_date)  # income
      create_transaction(account: @account, amount: 800, date: 3.months.ago.to_date)    # expense
      create_transaction(account: @account, amount: 800, date: 2.months.ago.to_date)    # expense
      create_transaction(account: @account, amount: 800, date: 1.month.ago.to_date)     # expense
    end
end
