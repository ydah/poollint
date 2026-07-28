# frozen_string_literal: true

multi_database_url = ENV.fetch(
  "DATABASE_URL",
  "postgresql://postgres:postgres@127.0.0.1:55432/poollint_test"
)

ActiveRecord::Base.configurations = {
  "default_env" => {
    "guard_primary" => { "url" => multi_database_url },
    "guard_secondary" => { "url" => multi_database_url }
  }
}

class PoolLintConnectedRecord < ActiveRecord::Base
  self.abstract_class = true
  connects_to database: { writing: :guard_primary, reading: :guard_secondary }
end

RSpec.describe PoolLint::Hooks, :postgresql do
  before do
    PoolLint.reset_configuration!(environment: "production")
    PoolLint.configuration.logger = instance_spy(Logger)
    PoolLint.install!
  end

  it "maintains independent baselines across connects_to roles" do
    primary = PoolLintConnectedRecord.connected_to(role: :writing) do
      PoolLintConnectedRecord.connection_pool.checkout
    end
    secondary = PoolLintConnectedRecord.connected_to(role: :reading) do
      PoolLintConnectedRecord.connection_pool.checkout
    end
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
