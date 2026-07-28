# frozen_string_literal: true

require "active_record"

class PoolLintMysql2Record < ActiveRecord::Base
  self.abstract_class = true
end

class PoolLintTrilogyRecord < ActiveRecord::Base
  self.abstract_class = true
end

MYSQL_CONNECTION = {
  host: ENV.fetch("MYSQL_HOST", "127.0.0.1"),
  port: Integer(ENV.fetch("MYSQL_PORT", "33306")),
  database: ENV.fetch("MYSQL_DATABASE", "poollint_test"),
  username: ENV.fetch("MYSQL_USERNAME", "root"),
  password: ENV.fetch("MYSQL_PASSWORD", "mysql"),
  pool: 5,
  checkout_timeout: 1
}.freeze

PoolLintMysql2Record.establish_connection(MYSQL_CONNECTION.merge(adapter: "mysql2"))
PoolLintTrilogyRecord.establish_connection(MYSQL_CONNECTION.merge(adapter: "trilogy"))

module MySQLHelpers
  ALL_MYSQL_RECORDS = {
    mysql2: PoolLintMysql2Record,
    trilogy: PoolLintTrilogyRecord
  }.freeze
  REQUESTED_ADAPTER = ENV["MYSQL_ADAPTER"]&.to_sym
  MYSQL_RECORDS = if REQUESTED_ADAPTER
                    { REQUESTED_ADAPTER => ALL_MYSQL_RECORDS.fetch(REQUESTED_ADAPTER) }.freeze
                  else
                    ALL_MYSQL_RECORDS
                  end

  def with_mysql_connection(adapter)
    pool = MYSQL_RECORDS.fetch(adapter).connection_pool
    connection = pool.checkout
    reset_mysql_session(connection)
    PoolLint::ConnectionState.remove(connection)
    yield connection
  ensure
    if connection
      reset_mysql_session(connection)
      PoolLint::ConnectionState.remove(connection)
      pool.checkin(connection)
    end
  end

  def reset_mysql_session(connection)
    PoolLint::ExecutionState.while_inspecting do
      PoolLint::DEFAULT_MYSQL_SETTINGS.each do |name|
        connection.execute("SET SESSION #{name} = DEFAULT")
      end
      connection.execute("SELECT RELEASE_ALL_LOCKS()")
    end
  end
end

RSpec.configure do |config|
  config.include MySQLHelpers, :mysql

  config.after(:suite) do
    MySQLHelpers::MYSQL_RECORDS.each_value do |record|
      record.connection_handler.clear_all_connections!(:all)
    end
  end
end
