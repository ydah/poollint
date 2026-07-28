# frozen_string_literal: true

RSpec.describe PoolLint::Hooks, :postgresql do
  before do
    PoolLint.reset_configuration!(environment: "production")
    PoolLint.install!
    PoolLint.configuration.logger = instance_spy(Logger)
  end

  it "reports a leaked setting when the connection is borrowed again" do
    pool = PoolLintPostgreSQLRecord.connection_pool
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(
      PoolLint::Notifier::EVENT_NAME
    ) do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end

    leaked_connection = pool.checkout
    reset_postgresql_session(leaked_connection)
    leaked_connection.execute("SET application_name = 'leaked-by-hook'")
    pool.checkin(leaked_connection)

    inspected_connection = pool.checkout

    expect(inspected_connection).to be(leaked_connection)
    expect(events.last.payload[:setting_changes].first[:name]).to eq("application_name")
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    if inspected_connection
      reset_postgresql_session(inspected_connection)
      PoolLint::ConnectionState.remove(inspected_connection)
      pool.checkin(inspected_connection)
    end
  end
end
