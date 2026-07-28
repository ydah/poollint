# frozen_string_literal: true

module PoolLint
  module Inspectors
    class PostgreSQLCapture
      def initialize(configuration)
        @configuration = configuration
      end

      def call(connection, names)
        snapshot = nil
        ExecutionState.while_inspecting do
          connection.transaction(requires_new: true, joinable: false) do
            original_timeout = capture_statement_timeout(connection, names)
            apply_timeout(connection)
            snapshot = yield
            restore_statement_timeout(snapshot, original_timeout)
            raise ActiveRecord::Rollback
          end
        end
        snapshot
      rescue StandardError => e
        raise InspectionTimeout, "inspection exceeded statement_timeout" if query_canceled?(e)

        raise
      end

      private

      def apply_timeout(connection)
        timeout_ms = (@configuration.inspection_timeout * 1000).ceil
        connection.execute("SET LOCAL statement_timeout = #{timeout_ms}")
      end

      def capture_statement_timeout(connection, names)
        return unless names.include?("statement_timeout")

        connection.select_value("SELECT current_setting('statement_timeout')")
      end

      def query_canceled?(error)
        active_record_timeout = defined?(ActiveRecord::QueryCanceled) &&
                                error.is_a?(ActiveRecord::QueryCanceled)
        active_record_timeout || error.cause&.class&.name == "PG::QueryCanceled"
      end

      def restore_statement_timeout(snapshot, original_timeout)
        return unless original_timeout

        captured = snapshot.settings.fetch("statement_timeout")
        snapshot.settings["statement_timeout"] = captured.class.new(
          setting: original_timeout,
          reset_value: captured.reset_value
        )
      end
    end
  end
end
