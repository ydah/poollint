# frozen_string_literal: true

RSpec.describe PoolLint::Hooks, :postgresql do
  before do
    PoolLint.reset_configuration!(environment: "production")
    PoolLint.configuration.logger = instance_spy(Logger)
    PoolLint.install!
  end

  it "detects a role left for the next checkout" do
    events = run_pool_cycle { |connection| connection.execute("SET ROLE postgres") }

    expect(changed_setting_names(events)).to include("role")
  end

  it "detects a setting while returning the connection" do
    PoolLint.configuration.inspection_point = :checkin
    events = run_pool_cycle do |connection|
      connection.execute("SET search_path = pg_catalog, public")
    end

    expect(changed_setting_names(events)).to include("search_path")
  end

  it "detects a session advisory lock" do
    events = run_pool_cycle { |connection| connection.execute("SELECT pg_advisory_lock(101)") }

    expect(events.first.payload[:advisory_locks]).not_to be_empty
  end

  it "detects state left on an exception path" do
    events = run_pool_cycle do |connection|
      connection.execute("SET application_name = 'exception-path'")
      raise "application failure"
    rescue RuntimeError
      nil
    end

    expect(changed_setting_names(events)).to include("application_name")
  end

  it "detects a custom GUC" do
    events = run_pool_cycle do |connection|
      connection.execute("SET myapp.tenant_id = 'tenant-42'")
    end

    expect(changed_setting_names(events)).to include("myapp.tenant_id")
  end

  it "does not report a reset role" do
    events = run_pool_cycle do |connection|
      connection.execute("SET ROLE postgres")
      connection.execute("RESET ROLE")
    end

    expect(events).to be_empty
  end

  it "does not report SET LOCAL" do
    events = run_pool_cycle do |connection|
      connection.transaction do
        connection.execute("SET LOCAL search_path = pg_catalog")
      end
    end

    expect(events).to be_empty
  end

  it "does not report a transaction advisory lock" do
    events = run_pool_cycle do |connection|
      connection.transaction do
        connection.execute("SELECT pg_advisory_xact_lock(102)")
      end
    end

    expect(events).to be_empty
  end

  it "does not report a released session advisory lock" do
    events = run_pool_cycle do |connection|
      connection.execute("SELECT pg_advisory_lock(103)")
      connection.execute("SELECT pg_advisory_unlock_all()")
    end

    expect(events).to be_empty
  end

  it "does not report a reset custom GUC" do
    events = run_pool_cycle do |connection|
      connection.execute("SET myapp.tenant_id = 'tenant-42'")
      connection.execute("RESET myapp.tenant_id")
    end

    expect(events).to be_empty
  end

  private

  def changed_setting_names(events)
    events.flat_map do |event|
      event.payload[:setting_changes].map { |change| change[:name] }
    end
  end

  def prepare_connection(pool)
    connection = pool.checkout
    reset_postgresql_session(connection)
    PoolLint::ConnectionState.remove(connection)
    PoolLint::InspectionRunner.call(connection, :checkout)
    connection
  end

  def run_pool_cycle
    pool = PoolLintPostgreSQLRecord.connection_pool
    connection = prepare_connection(pool)
    events = []
    subscriber = subscribe(events)
    yield connection
    pool.checkin(connection)
    checked_out = pool.checkout
    expect(checked_out).to be(connection)
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    cleanup_connection(pool, checked_out || connection)
  end

  def subscribe(events)
    ActiveSupport::Notifications.subscribe(PoolLint::Notifier::EVENT_NAME) do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end
  end

  def cleanup_connection(pool, connection)
    return unless connection

    reset_postgresql_session(connection)
    PoolLint::ConnectionState.remove(connection)
    pool.checkin(connection) if connection.in_use?
  end
end
