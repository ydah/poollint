# frozen_string_literal: true

RSpec.describe PoolLint::Hooks, :mysql do
  before do
    PoolLint.reset_configuration!(environment: "production")
    PoolLint.configuration.logger = instance_spy(Logger)
    PoolLint.install!
  end

  MySQLHelpers::MYSQL_RECORDS.each do |adapter, record|
    it "detects a leaked MySQL setting through #{adapter} checkout hooks" do
      events = run_mysql_pool_cycle(record) do |connection|
        connection.execute("SET SESSION max_execution_time = 1234")
      end

      changes = events.flat_map { |event| event.payload[:setting_changes] }
      expect(changes.map { |change| change[:name] }).to include("max_execution_time")
    end

    it "detects a leaked GET_LOCK through #{adapter} checkout hooks" do
      events = run_mysql_pool_cycle(record) do |connection|
        connection.execute("SELECT GET_LOCK('hooks/#{adapter}', 0)")
      end

      locks = events.flat_map { |event| event.payload[:user_level_locks] }
      expect(locks).to include(hash_including(name: "hooks/#{adapter}", confidence: :confirmed))
    end
  end

  private

  def run_mysql_pool_cycle(record)
    pool = record.connection_pool
    connection = prepare_mysql_connection(pool)
    events = []
    subscriber = subscribe(events)
    yield connection
    pool.checkin(connection)
    checked_out = pool.checkout
    expect(checked_out).to be(connection)
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    cleanup_mysql_connection(pool, checked_out || connection)
  end

  def prepare_mysql_connection(pool)
    connection = pool.checkout
    reset_mysql_session(connection)
    PoolLint::ConnectionState.remove(connection)
    PoolLint::InspectionRunner.call(connection, :checkout)
    connection
  end

  def subscribe(events)
    ActiveSupport::Notifications.subscribe(PoolLint::Notifier::EVENT_NAME) do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end
  end

  def cleanup_mysql_connection(pool, connection)
    return unless connection

    reset_mysql_session(connection)
    PoolLint::ConnectionState.remove(connection)
    pool.checkin(connection) if connection.in_use?
  end
end
