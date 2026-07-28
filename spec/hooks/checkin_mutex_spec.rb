# frozen_string_literal: true

class PoolLintMutexProbeRecord < ActiveRecord::Base
  self.abstract_class = true
end

PoolLintMutexProbeRecord.establish_connection(
  url: ENV.fetch(
    "DATABASE_URL",
    "postgresql://postgres:postgres@127.0.0.1:55432/poollint_test"
  ),
  pool: 2,
  checkout_timeout: 1
)

RSpec.describe PoolLint::Hooks, :postgresql do
  before do
    PoolLint.reset_configuration!(environment: "production")
    PoolLint.configuration.logger = instance_spy(Logger)
    PoolLint.install!
  end

  it "shows that checkin inspection blocks checkout while holding the pool mutex" do
    pool = PoolLintMutexProbeRecord.connection_pool
    first = pool.checkout
    second = pool.checkout
    reset_postgresql_session(first)
    reset_postgresql_session(second)
    pool.checkin(first)
    pool.checkin(second)

    entered_notifier = Queue.new
    PoolLint.configuration.inspection_point = :checkin
    PoolLint.configuration.ignore_if = lambda do |_report|
      entered_notifier << true
      sleep 0.1
      false
    end

    worker_connection = nil
    checkin_thread = Thread.new do
      worker_connection = pool.checkout
      worker_connection.execute("SET application_name = 'mutex-probe'")
      pool.checkin(worker_connection)
    end
    entered_notifier.pop
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    borrowed = pool.checkout
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    checkin_thread.join

    expect(elapsed).to be >= 0.08
  ensure
    checkin_thread&.join
    PoolLint.configuration.inspection_point = :checkout
    PoolLint.configuration.ignore_if = nil
    [borrowed, worker_connection].compact.uniq.each do |connection|
      reset_postgresql_session(connection)
      PoolLint::ConnectionState.remove(connection)
      pool.checkin(connection) if connection.in_use?
    end
  end
end
