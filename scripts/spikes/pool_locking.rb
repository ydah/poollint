# frozen_string_literal: true

require "json"

version = ENV.fetch("AR_VERSION")
gem "activerecord", version
gem "activemodel", version
gem "activesupport", version
gem "pg", "~> 1.5"

require "active_record"

adapter_class = ActiveRecord::ConnectionAdapters::AbstractAdapter
module SpikeRecords
end

def build_pool
  name = :"Record#{SpikeRecords.constants.length + 1}"
  record_class = Class.new(ActiveRecord::Base) do
    self.abstract_class = true
  end
  SpikeRecords.const_set(name, record_class)
  record_class.establish_connection(
    url: ENV.fetch(
      "DATABASE_URL",
      "postgresql://postgres:postgres@127.0.0.1:55432/poollint_test"
    ),
    pool: 1,
    checkout_timeout: 0.05
  )
  record_class.connection_pool
end

def with_callback(adapter_class, event, callback)
  adapter_class.set_callback(event, :before, callback)
  yield
ensure
  adapter_class.skip_callback(event, :before, callback)
end

ownership_pool = build_pool
ownership = {}

checkout_probe = proc do
  ownership[:checkout_pool_mutex_owned] = ownership_pool.send(:mon_owned?)
end

connection = with_callback(adapter_class, :checkout, checkout_probe) do
  ownership_pool.checkout
end

checkin_probe = proc do
  ownership[:checkin_pool_mutex_owned] = ownership_pool.send(:mon_owned?)
end

with_callback(adapter_class, :checkin, checkin_probe) do
  ownership_pool.checkin(connection)
end

checkout_failure_pool = build_pool
checkout_failure = proc { raise "checkout callback failure" }

begin
  with_callback(adapter_class, :checkout, checkout_failure) do
    checkout_failure_pool.checkout
  end
rescue RuntimeError
  ownership[:checkout_exception_raised] = true
end

replacement = checkout_failure_pool.checkout
ownership[:checkout_recovers_after_callback_exception] = !replacement.nil?
checkout_failure_pool.checkin(replacement)

checkin_failure_pool = build_pool
stranded = checkin_failure_pool.checkout
checkin_failure = proc { raise "checkin callback failure" }

begin
  with_callback(adapter_class, :checkin, checkin_failure) do
    checkin_failure_pool.checkin(stranded)
  end
rescue RuntimeError
  ownership[:checkin_exception_raised] = true
end

begin
  checkin_failure_pool.checkout(0.05)
  ownership[:checkin_recovers_after_callback_exception] = true
rescue ActiveRecord::ConnectionTimeoutError
  ownership[:checkin_recovers_after_callback_exception] = false
ensure
  checkin_failure_pool.remove(stranded)
  stranded.disconnect!
end

puts JSON.pretty_generate(ownership)
