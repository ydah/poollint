# frozen_string_literal: true

class PoolLintSecondaryRecord < ActiveRecord::Base
  self.abstract_class = true
end

PoolLintSecondaryRecord.establish_connection(
  url: ENV.fetch(
    "DATABASE_URL",
    "postgresql://postgres:postgres@127.0.0.1:55432/poollint_test"
  ),
  pool: 1,
  checkout_timeout: 1
)

RSpec.describe PoolLint::Hooks, :postgresql do
  before do
    PoolLint.reset_configuration!(environment: "production")
    PoolLint.configuration.logger = instance_spy(Logger)
    PoolLint.install!
  end

  it "maintains independent baselines for separate database pools" do
    primary = PoolLintPostgreSQLRecord.connection_pool.checkout
    secondary = PoolLintSecondaryRecord.connection_pool.checkout
    reset_postgresql_session(primary)
    reset_postgresql_session(secondary)

    primary_state = PoolLint.connection_state(primary)
    secondary_state = PoolLint.connection_state(secondary)
    primary.execute("SET myapp.database_id = 'primary'")
    secondary.execute("SET myapp.database_id = 'secondary'")

    expect(primary_state).not_to be(secondary_state)
    expect(primary_state.monitored_settings).to eq(["myapp.database_id"])
    expect(secondary_state.monitored_settings).to eq(["myapp.database_id"])
  ensure
    [primary, secondary].compact.each do |connection|
      reset_postgresql_session(connection)
      PoolLint::ConnectionState.remove(connection)
      connection.pool.checkin(connection)
    end
  end
end
