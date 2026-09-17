# frozen_string_literal: true

module QueryCountTestHelper
  # The queries a block runs, leaving out cached ones, schema lookups and transactions
  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:cached] || payload[:name].in?(%w[SCHEMA TRANSACTION]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end

  # Adds records and runs the request, then adds as many again and reruns it: a page
  # that preloads what it shows needs the same number of queries both times. Adding
  # the same kinds of records before both runs keeps preloads that have nothing to
  # load, and first-visit work, out of the comparison.
  def assert_queries_independent_of(add_records, &request)
    add_records.call
    request.call
    few = count_queries(&request)
    add_records.call
    many = count_queries(&request)

    assert_response :success
    assert_equal few, many, "the request ran #{many - few} more queries after adding records"
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include QueryCountTestHelper
end
