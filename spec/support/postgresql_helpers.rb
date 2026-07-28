# frozen_string_literal: true

require "active_record"

class PoolLintPostgreSQLRecord < ActiveRecord::Base
  self.abstract_class = true
end

PoolLintPostgreSQLRecord.establish_connection(
  url: ENV.fetch(
    "DATABASE_URL",
    "postgresql://postgres:postgres@127.0.0.1:55432/poollint_test"
  ),
  pool: 5,
  checkout_timeout: 1
)

module PostgreSQLHelpers
  def with_postgresql_connection
    pool = PoolLintPostgreSQLRecord.connection_pool
    connection = pool.checkout
    reset_postgresql_session(connection)
    PoolLint::ConnectionState.remove(connection)
    yield connection
  ensure
    if connection
      reset_postgresql_session(connection)
      PoolLint::ConnectionState.remove(connection)
      pool.checkin(connection)
    end
  end

  def reset_postgresql_session(connection)
    PoolLint::ExecutionState.while_inspecting do
      connection.execute("RESET ALL")
      connection.execute("RESET ROLE")
      connection.execute("RESET SESSION AUTHORIZATION")
      connection.execute("SELECT pg_advisory_unlock_all()")
    end
  end
end

RSpec.configure do |config|
  config.after(:suite) do
    PoolLintPostgreSQLRecord.connection_handler.clear_all_connections!
  end
end
