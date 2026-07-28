# frozen_string_literal: true

module PoolLint
  class InspectionRunner
    class << self
      def call(connection, inspection_point)
        configuration = PoolLint.configuration
        state = PoolLint.connection_state(connection)

        unless state.baseline?
          Inspectors::PostgreSQL.new(configuration).establish_baseline(connection, state)
        end
        return unless configuration.inspection_point == inspection_point
        return unless state.dirty?
        return if rand >= configuration.check_probability

        inspect_and_notify(connection, state, inspection_point, configuration)
      rescue LeakDetected
        raise
      rescue StandardError => e
        PoolLint.log_warning(
          "inspection skipped after #{e.class}: #{e.message}"
        )
      end

      private

      def inspect_and_notify(connection, state, inspection_point, configuration)
        inspector = Inspectors::PostgreSQL.new(configuration)
        report = inspector.inspect(connection, state, inspection_point: inspection_point)
        Notifier.new(configuration).call(report) if report
      end
    end
  end
end
