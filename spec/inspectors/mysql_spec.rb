# frozen_string_literal: true

RSpec.describe PoolLint::Inspectors::MySQL, :mysql do
  def mark_dirty(state, setting: nil, operation: nil, lock_name: nil)
    state.mark_dirty(
      kind: operation ? :user_level_lock : :set,
      setting: setting,
      sql: setting ? "SET SESSION #{setting} = 1234" : "SELECT GET_LOCK('#{lock_name}', 0)",
      call_site: "mysql_spec.rb:1",
      lock_operation: operation,
      lock_name: lock_name
    )
  end

  def fallback_inspector
    fallback_class = Class.new(described_class) do
      private

      def capture_confirmed_user_locks(_connection)
        raise ActiveRecord::StatementInvalid, "performance_schema denied"
      end
    end
    fallback_class.new(PoolLint.configuration)
  end

  MySQLHelpers::MYSQL_RECORDS.each_key do |adapter|
    context "with #{adapter}" do
      around do |example|
        PoolLint.reset_configuration!(environment: "production")
        PoolLint.configuration.logger = Logger.new(IO::NULL)
        with_mysql_connection(adapter) do |connection|
          @connection = connection
          @state = PoolLint.connection_state(connection)
          @inspector = described_class.new(PoolLint.configuration)
          @inspector.establish_baseline(connection, @state)
          example.run
        end
      end

      it "reports a changed watched session variable" do
        @connection.execute("SET SESSION max_execution_time = 1234")
        mark_dirty(@state, setting: "max_execution_time")

        report = @inspector.inspect(@connection, @state, inspection_point: :checkout)

        expect(report.setting_changes.first.to_h).to include(
          name: "max_execution_time",
          baseline: "0",
          current: "1234"
        )
      end

      it "does not report a reset session variable" do
        @connection.execute("SET SESSION max_execution_time = 1234")
        @connection.execute("SET SESSION max_execution_time = DEFAULT")
        mark_dirty(@state, setting: "max_execution_time")

        expect(@inspector.inspect(@connection, @state, inspection_point: :checkout)).to be_nil
      end

      it "confirms a GET_LOCK owned by the current connection" do
        @connection.execute("SELECT GET_LOCK('orders/confirmed', 0)")
        mark_dirty(
          @state,
          operation: :acquire,
          lock_name: "orders/confirmed"
        )

        report = @inspector.inspect(@connection, @state, inspection_point: :checkout)

        expect(report.user_level_locks.first.to_h).to include(
          name: "orders/confirmed",
          confidence: :confirmed,
          status: "GRANTED"
        )
      end

      it "does not report a released user-level lock" do
        @connection.execute("SELECT GET_LOCK('orders/released', 0)")
        @connection.execute("SELECT RELEASE_LOCK('orders/released')")
        mark_dirty(@state, operation: :release, lock_name: "orders/released")

        expect(@inspector.inspect(@connection, @state, inspection_point: :checkout)).to be_nil
      end

      it "does not report a user-level lock owned by another connection" do
        pool = MySQLHelpers::MYSQL_RECORDS.fetch(adapter).connection_pool
        other_connection = pool.checkout
        reset_mysql_session(other_connection)
        other_connection.execute("SELECT GET_LOCK('orders/other-connection', 0)")
        mark_dirty(@state, operation: :acquire, lock_name: "orders/other-connection")

        expect(@inspector.inspect(@connection, @state, inspection_point: :checkout)).to be_nil
      ensure
        if other_connection
          reset_mysql_session(other_connection)
          PoolLint::ConnectionState.remove(other_connection)
          pool.checkin(other_connection)
        end
      end

      it "falls back to inferred lock balances when Performance Schema is unavailable" do
        mark_dirty(@state, operation: :acquire, lock_name: "orders/inferred")

        report = fallback_inspector.inspect(@connection, @state, inspection_point: :checkout)

        expect(report.user_level_locks.first.to_h).to include(
          name: "orders/inferred",
          acquisition_count: 1,
          confidence: :inferred
        )
      end
    end
  end
end
