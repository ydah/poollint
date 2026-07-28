# frozen_string_literal: true

module PoolLint
  class InspectionRunner
    class << self
      def call(connection, inspection_point)
        configuration = PoolLint.configuration
        inspector = Inspectors.for(connection, configuration)
        return unless inspector

        state = PoolLint.connection_state(connection)
        establish_baseline(inspector, connection, state)
        return unless configuration.inspection_point == inspection_point
        return unless state.dirty?
        return if rand >= configuration.check_probability

        inspect_and_notify(connection, state, inspection_point, configuration, inspector)
      rescue LeakDetected
        raise
      rescue StandardError => e
        PoolLint.log_warning(
          "inspection skipped after #{e.class}: #{e.message}"
        )
      end

      private

      def establish_baseline(inspector, connection, state)
        inspector.establish_baseline(connection, state) unless state.baseline?
      end

      def inspect_and_notify(connection, state, inspection_point, configuration, inspector)
        report = inspector.inspect(connection, state, inspection_point: inspection_point)
        Notifier.new(configuration).call(report) if report
      end
    end
  end
end
