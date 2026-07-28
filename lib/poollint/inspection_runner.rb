# frozen_string_literal: true

module PoolLint
  class InspectionRunner
    class << self
      def call(connection, inspection_point)
        configuration = PoolLint.configuration
        inspector_class = Inspectors.for(connection)
        return unless inspector_class

        state = PoolLint.connection_state(connection)
        establish_baseline(inspector_class, connection, state, configuration)
        return unless configuration.inspection_point == inspection_point
        return unless state.dirty?
        return if rand >= configuration.check_probability

        inspect_and_notify(connection, state, inspection_point, configuration, inspector_class)
      rescue LeakDetected
        raise
      rescue StandardError => e
        PoolLint.log_warning(
          "inspection skipped after #{e.class}: #{e.message}"
        )
      end

      private

      def establish_baseline(inspector_class, connection, state, configuration)
        return if state.baseline?

        inspector_class.new(configuration).establish_baseline(connection, state)
      end

      def inspect_and_notify(connection, state, inspection_point, configuration, inspector_class)
        inspector = inspector_class.new(configuration)
        report = inspector.inspect(connection, state, inspection_point: inspection_point)
        Notifier.new(configuration).call(report) if report
      end
    end
  end
end
